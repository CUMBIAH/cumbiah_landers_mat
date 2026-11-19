%% Test: locate the landers from the close boat passes only
%
% LOCATE_ARRAY fits the position, heading, pitch and roll of each lander to
% every boat calibration click, out to ~1.4 km. Beyond ~80 m the slant
% angles are biased by a few degrees (refraction and, it seems, the seabed
% echo of the boat noise - see propagation/assess_lander_location_refraction.m).
% Here each lander is located again with LOCATEPLATFORM's 'maxrange' so the
% heading and the fine search only use clicks with the boat within MAXRANGE
% of the lander, and the result is compared with the saved fit:
%   - the change in position, heading, pitch and roll
%   - the slant residual (measured - straight line) against range for both
%
% The new fit is saved to a separate file, NEWFILE, beside the array file;
% the array file LOCALISEPORPOISES uses is not touched.
clear
close all

country    = 'Denmark';
deployment = 1;
landers    = [1 2 3];
depth      = 17;        % as LOCATE_ARRAY
maxrange   = 60;        % m
recalculate = false;

%% Paths
here = fileparts(mfilename('fullpath'));
folders = strsplit(genpath(fileparts(fileparts(here))), pathsep);
[~, names] = cellfun(@fileparts, folders, 'UniformOutput', false);
folders = folders(~ismember(names, {'_old', '_test', '_tests', ''}) & ~contains(folders, [filesep '.']));
addpath(strjoin(folders, pathsep));

superfolder = getlandersuperfolder(country);
oldfile = fullfile(superfolder, sprintf('lander_array_locations_dep%d.mat', deployment));
newfile = fullfile(superfolder, sprintf('lander_array_locations_dep%d_maxrange%g.mat', deployment, maxrange));
outfolder = fullfile(superfolder, 'propagation', 'lander_location');
if ~isfolder(outfolder), mkdir(outfolder); end
old = load(oldfile);

%% Locate each lander from the close passes
resfile = fullfile(outfolder, sprintf('locateplatform_maxrange%g_dep%d.mat', maxrange, deployment));
if isfile(resfile) && ~recalculate
    load(resfile, 'R');
else
    keep = {'landernumber', 'location', 'locationfine', 'hprfinal', 'headingoffset', ...
        'headingstd', 'rtctimeoffset', 'chi2', 'chi2fine'};
    for i = 1:numel(landers)
        [startTime, ~, serialnumber] = getlanderdeploymentinfo(landers(i), deployment, country);
        data = getlanderpaths(serialnumber, startTime);
        t0 = tic;
        res = locateplatform(data, 'depth', depth, 'gridlims', [-40 40], ...
            'gridcenter', data.droplocation, 'maxrange', maxrange);
        fprintf('Lander %d located in %.0f s from %d clicks\n', landers(i), toc(t0), sum(res.validclk));
        R(i) = struct('lander', landers(i), 'res', rmfield(res, {'chi2surf', 'chi2surffine'})); %#ok<SAGROW>
        for k = 1:numel(keep)
            locs(i).(keep{k}) = res.(keep{k}); %#ok<SAGROW>
        end
        locs(i).maxrange = maxrange; %#ok<SAGROW>
        locs(i).nclicks = sum(res.validclk); %#ok<SAGROW>
    end
    save(resfile, 'R', '-v7.3');
    locstable = struct2table(locs); %#ok<NASGU>
    save(newfile, 'locstable', 'landers', 'depth', 'deployment', 'maxrange');
    fprintf('Saved %s\n', newfile);
end
new = load(newfile);

%% Compare
fprintf('\n%-8s %10s %10s %10s %10s %10s %10s %10s\n', 'lander', 'move (m)', 'E (m)', 'N (m)', ...
    'dhead', 'dpitch', 'droll', 'hdg std');
for i = 1:numel(landers)
    a = old.locstable(old.locstable.landernumber == landers(i), :);
    b = new.locstable(new.locstable.landernumber == landers(i), :);
    [~, de, dn] = latLong2meters(a.locationfine(1), a.locationfine(2), b.locationfine(1), b.locationfine(2));
    dh = b.hprfinal - a.hprfinal;
    dh(1) = mod(dh(1) + 180, 360) - 180;
    fprintf('%-8d %10.1f %+10.1f %+10.1f %+10.1f %+10.1f %+10.1f %5.1f->%4.1f\n', landers(i), hypot(de, dn), ...
        de, dn, dh, a.headingstd, b.headingstd);
    fprintf('         old hpr %s, new hpr %s\n', mat2str(a.hprfinal, 3), mat2str(b.hprfinal, 3));
end
% the distances between the landers, which the localiser depends on
pairs = nchoosek(1:numel(landers), 2);
for q = 1:size(pairs, 1)
    i = pairs(q,1); j = pairs(q,2);
    d0 = latLong2meters(old.locstable.locationfine(i,1), old.locstable.locationfine(i,2), ...
        old.locstable.locationfine(j,1), old.locstable.locationfine(j,2));
    d1 = latLong2meters(new.locstable.locationfine(i,1), new.locstable.locationfine(i,2), ...
        new.locstable.locationfine(j,1), new.locstable.locationfine(j,2));
    fprintf('Landers %d-%d: %.1f m -> %.1f m\n', landers(i), landers(j), d0, d1);
end

%% Slant residuals against range, old and new fit, on the same clicks
f = figure('Position', [50 50 1400 360*numel(landers)], 'Color', 'w');
tl = tiledlayout(numel(landers), 1, 'TileSpacing', 'compact');
fits = {old.locstable, new.locstable};
fitlabels = {'all clicks (current)', sprintf('clicks within %g m', maxrange)};
cols = [0.15 0.35 0.75; 0.85 0.25 0.1];
for i = 1:numel(landers)
    res = R(i).res;
    src = res.srcclklocations;                       % datenum lat lon depth
    ok = ~any(isnan(src(:,2:3)), 2);
    ax = nexttile(tl); hold(ax, 'on');
    h = gobjects(1, 2);
    for f2 = 1:2
        L = fits{f2}(fits{f2}.landernumber == landers(i), :);
        r = nan(size(src, 1), 1);
        for k = find(ok)'
            r(k) = latLong2meters(L.locationfine(1), L.locationfine(2), src(k,2), src(k,3));
        end
        geo = atand(src(:,4)./r);
        meas = rad2deg(rotate_bearings(res.clkgeobearings, L.hprfinal));
        resid = meas(:,2) - geo;
        scatter(ax, r, resid, 4, cols(f2,:), 'filled', 'MarkerFaceAlpha', 0.15);
        edges = [0:10:100, 125:25:max(r) + 25];
        bin = discretize(r, edges);
        g = ~isnan(bin) & ~isnan(resid);
        med = accumarray(bin(g), resid(g), [numel(edges)-1 1], @median, NaN);
        h(f2) = plot(ax, (edges(1:end-1) + edges(2:end))/2, med, '-', 'Color', cols(f2,:), 'LineWidth', 2.5);
    end
    xline(ax, maxrange, 'k--');
    yline(ax, 0, 'k');
    set(ax, 'XScale', 'log'); xlim(ax, [5 1500]); ylim(ax, [-15 15]);
    grid(ax, 'on'); box(ax, 'on');
    ylabel(ax, 'Slant - straight line (deg)');
    title(ax, sprintf('Lander %d', landers(i)));
    legend(ax, h, strcat("median, fit to ", fitlabels), 'Location', 'southeast');
end
xlabel(ax, 'Range to the boat (m)');
exportgraphics(f, fullfile(outfolder, sprintf('locate_maxrange%g_residuals.png', maxrange)), 'Resolution', 150);
fprintf('Saved %s\n', fullfile(outfolder, sprintf('locate_maxrange%g_residuals.png', maxrange)));
