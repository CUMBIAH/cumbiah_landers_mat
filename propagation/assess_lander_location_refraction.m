%ASSESS_LANDER_LOCATION_REFRACTION How much could refraction move the lander
%positions and orientations that LOCATE_ARRAY finds from the boat?
%
%   LOCATEPLATFORM locates each lander from the bearing and slant angle of
%   the boat's cavitation noise, with the boat 1 m deep and the lander at
%   17 m, assuming straight lines. The slant angle is what gives the range
%   to the boat, so a refraction bias in the slant moves the lander, and a
%   bias that changes with direction could be taken up as pitch or roll.
%
%   For each lander of deployment 1 this script
%     1. reads the boat calibration clicks and the boat track as
%        LOCATEPLATFORM does, at the clock offset it found, and computes
%        the measured slant (with the fitted heading, pitch and roll) minus
%        the straight line slant from the fitted position, against range
%     2. predicts the slant bias of a source 1 m deep at those ranges for
%        each site CTD cast (propagation tables, MAKE_PROPAGATION_TABLES)
%     3. simulates the boat clicks as they would arrive through each cast
%        (true bearings, ray traced slants, no noise) and refits position,
%        heading, pitch and roll with the straight line model, with the
%        weights of ST_LOC_CHI2 (slant 3 deg, bearing 5 deg). The fit's
%        offset from the true position is the bias refraction would give
%
%   Plots go to <Denmark>/propagation/lander_location.
%
%   See also LOCATE_ARRAY, LOCATEPLATFORM, MAKE_PROPAGATION_TABLE.

clear; close all;
here = fileparts(mfilename('fullpath'));
addpath(here);

country = 'Denmark';
deployment = 1;
landers = [1 2 3];
srcdepth = 1;           % depth of the boat noise, as LOCATEPLATFORM (m)
landerdepth = 17;       % as LOCATE_ARRAY (m)

superfolder = getlandersuperfolder(country);
A = load(fullfile(superfolder, sprintf('lander_array_locations_dep%d.mat', deployment)));
T = load(fullfile(superfolder, 'propagation', 'propagation_tables.mat'));
props = T.propagation;
outfolder = fullfile(superfolder, 'propagation', 'lander_location');
if ~isfolder(outfolder), mkdir(outfolder); end
proplabels = arrayfun(@(P) string(char(P.time, 'dd MMM yyyy HH:mm')), props);

% the slant a source SRCDEPTH deep arrives from at the lander, out to the
% longest boat range, for each cast, and a synthetic autumn profile: the
% surface cooled to the temperature of the bottom water, so a 4.5 m/s rise
% across the halocline at 10-14 m (the salinity step of the June casts) is
% all that is left - upward refracting, the opposite of September
P0 = props(1);
zsyn = P0.z;
csyn = 1470 + 4.5*min(max((zsyn - 10)/4, 0), 1);
profiles = [arrayfun(@(P) {P.z, P.c}, props, 'UniformOutput', false), {{zsyn, csyn}}];
proplabels = [proplabels, "synthetic autumn, +4.5 m/s at 10-14 m"];
rcurve = [1:2:50, 55:5:1600];
scurve = nan(numel(rcurve), numel(profiles));
for j = 1:numel(profiles)
    B = slant_refraction_bias(profiles{j}{1}, profiles{j}{2}, landerdepth, rcurve, srcdepth, ...
        'paths', 'D', 'angles', -89:0.01:1);
    s = fillmissing(B.D.slant, 'nearest');
    scurve(:,j) = s;
end
geocurve = atand((landerdepth - srcdepth)./rcurve');

for i = 1:numel(landers)
    L = A.locstable(A.locstable.landernumber == landers(i), :);
    [t0, ~, sn] = getlanderdeploymentinfo(landers(i), deployment, country);
    data = getlanderpaths(sn, t0);
    binaryfolder = fullfile(data.binaryfolder, char(data.startTime, 'yyyyMMdd'));
    clicks = [];
    for db = {data.sqlitedB, data.rawsqlitedB}
        if isempty(clicks) && isfile(db{1})
            clicks = import_clk_train(db{1}, binaryfolder, 'eventtype', 'bc');
        end
    end
    [~, k] = sort([clicks.date]); clicks = clicks(k);
    cb = decimate_bearings(clkstruct2bearings(clicks), 5);   % [datenum horiz slant] deg

    g = load(data.gpsfile);
    gps = [datenum(g.gpsdata.time), g.gpsdata.latitude, g.gpsdata.longitude];
    gps(1,:) = [];
    gps(:,1) = gps(:,1) + L.rtctimeoffset/86400;
    in = cb(:,1) > min(gps(:,1)) & cb(:,1) < max(gps(:,1));
    cb = cb(in,:);
    src = interpsrcloc(cb(:,1), gps, landerdepth, srcdepth);  % lat lon depth difference
    loc = L.locationfine;
    [~, ex, ny] = latLong2meters(loc(1), loc(2), src(:,1), src(:,2));
    r = hypot(ex, ny);
    az = atan2d(ex, ny);                                       % true bearing (deg)
    geo = atand(src(:,3)./r);                                  % straight line slant (deg)
    meas = rad2deg(rotate_bearings(deg2rad(cb(:,2:3)), L.hprfinal));
    R(i).lander = landers(i); %#ok<SAGROW>
    R(i).r = r; R(i).az = az; R(i).geo = geo; R(i).meas = meas; R(i).hpr = L.hprfinal;

    % predicted bias of each profile at these boat ranges and the fit it gives
    for j = 1:numel(profiles)
        ray = interp1(rcurve, scurve(:,j), r, 'linear', 'extrap');
        R(i).ray(:,j) = ray;
        R(i).fit(j,:) = refit([ex ny], [az ray], src(:,3));
    end
    fprintf('Lander %d: %d clicks, boat range %.0f-%.0f m (median %.0f m)\n', landers(i), numel(r), ...
        min(r), max(r), median(r));
    for j = 1:numel(profiles)
        f = R(i).fit(j,:);
        fprintf('   %s: position moves %.1f m (E %+.1f, N %+.1f), heading %+.2f, pitch %+.2f, roll %+.2f deg\n', ...
            proplabels(j), hypot(f(1), f(2)), f(1), f(2), f(3), f(4), f(5));
    end
end
save(fullfile(outfolder, 'lander_location_refraction.mat'), 'R', 'proplabels');

%% Plots
co = lines(numel(profiles));
f = figure('Position', [50 50 1400 380*numel(R)], 'Color', 'w');
tl = tiledlayout(numel(R), 2, 'TileSpacing', 'compact');
for i = 1:numel(R)
    ax = nexttile(tl); hold(ax, 'on');
    scatter(ax, R(i).r, R(i).meas(:,2) - R(i).geo, 6, [0.6 0.6 0.6], 'filled');
    for j = 1:numel(profiles)
        plot(ax, rcurve, scurve(:,j) - geocurve, '-', 'Color', co(j,:), 'LineWidth', 2);
    end
    % running median of the residuals
    edges = 0:25:max(R(i).r) + 25;
    bin = discretize(R(i).r, edges);
    med = accumarray(bin(~isnan(bin)), R(i).meas(~isnan(bin),2) - R(i).geo(~isnan(bin)), [numel(edges)-1 1], @median, NaN);
    plot(ax, edges(1:end-1) + 12.5, med, 'k-', 'LineWidth', 2);
    yline(ax, 0, 'k'); ylim(ax, [-15 15]); grid(ax, 'on'); box(ax, 'on');
    xlabel(ax, 'Range to the boat (m)'); ylabel(ax, 'Slant - straight line (deg)');
    title(ax, sprintf('Lander %d: measured residual (grey) and refraction bias', R(i).lander));
    xlim(ax, [0 max(R(i).r)]);
    legend(ax, ["clicks", proplabels, "median of the clicks"], 'Location', 'southeast', 'FontSize', 8);
    ax = nexttile(tl); hold(ax, 'on');
    histogram(ax, R(i).r, 0:5:max(250, max(R(i).r)));
    xlabel(ax, 'Range to the boat (m)'); ylabel(ax, 'Clicks'); grid(ax, 'on'); box(ax, 'on');
    title(ax, 'Ranges of the boat clicks used');
end
exportgraphics(f, fullfile(outfolder, 'boat_slant_residuals.png'), 'Resolution', 150);
fprintf('Plots in %s\n', outfolder);

%% ------------------------------------------------------------------------
function p = refit(xy, obs, dz)
% Fit [dE dN heading pitch roll] of a lander with straight line propagation
% to noise free bearings and slants OBS (deg) of sources at XY (m from the
% true position), DZ (m) above it. The weights are those of
% ST_LOC_CHI2. P is the fitted offset from the truth (m, deg).
errs = 3; errb = 5;
obsr = deg2rad(obs);
fun = @(q) cost(q, xy, obsr, dz, errs, errb);
p = fminsearch(fun, zeros(1, 5), optimset('TolX', 1e-4, 'TolFun', 1e-8, 'MaxFunEvals', 2e4, 'MaxIter', 2e4));
end

function c = cost(q, xy, obsr, dz, errs, errb)
% observations rotated by the trial orientation, against the straight line
% angles from the trial position
m = rad2deg(rotate_bearings(obsr, q(3:5)));
d = xy - q(1:2);
r = hypot(d(:,1), d(:,2));
b = atan2d(d(:,1), d(:,2));
s = atand(dz./r);
db = mod(m(:,1) - b + 180, 360) - 180;
c = mean(((m(:,2) - s)/errs).^2 + (db/errb).^2);
end
