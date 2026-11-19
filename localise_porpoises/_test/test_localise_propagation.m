%% Test: straight line against ray traced propagation for one event
%
% Localises the same period (TLIMS) as TEST_LOCALISE_ONE_EVENT twice with
% LOCALISEPORPOISES:
%   1. straight lines, at the sound speed of the CTD cast at the landers
%   2. ray traced propagation through the sound speed profile of the cast
%      (MAKE_PROPAGATION_TABLE), so refraction is allowed for
% The only difference between the two is how the time delays of each
% lander are predicted from a porpoise position, so any difference in the
% tracks is the refraction. The particle filter is random, so the random
% number generator is reset before each run.
%
% Plots (in OUTFOLDER):
%   1. both sets of tracks in a plan view and two side views
%   2. depth and horizontal range from the middle of the array against
%      time, for both
%   3. the change in depth against range (ray traced - straight line), at
%      the times of the straight line tracks
%
% The tables are made by propagation/make_propagation_tables.m. There is
% no CTD cast from deployment 1 (Oct 2024); CASTFILE picks the September
% 2025 cast at the array, which had a thermocline at 10-14 m - the worst
% case of the casts there.
%
% Needs the CUMBIAH library, soundnet, PAMGUARD, the CIBBRiNA soundtrap_4c
% code and the particle filter on the MATLAB path.
clear
close all

%% Inputs
country    = 'Denmark';
deployment = 1;
landers    = [1 2 3];

tlims = [datetime(2024, 10, 20, 15, 46, 0), datetime(2024, 10, 20, 15, 50, 30)];

castname = 'CC2043006_20250912_092555';  % the CTD cast used (September 2025, at the array)
relocalise = false;     % run the particle filter again even if the results are saved
minslant = -10;
nruns = 5;
particles = 1000;
maxrange = 150;         % circle around the array in the plan view (m)
seed = 1;               % random number seed of each run

%% Paths
here = fileparts(mfilename('fullpath'));
folders = strsplit(genpath(fileparts(fileparts(here))), pathsep);
[~, names] = cellfun(@fileparts, folders, 'UniformOutput', false);
folders = folders(~ismember(names, {'_old', '_test', '_tests', ''}) & ~contains(folders, [filesep '.']));
addpath(strjoin(folders, pathsep));

superfolder = getlandersuperfolder(country);
arrayfile = fullfile(superfolder, sprintf('lander_array_locations_dep%d.mat', deployment));
name = sprintf('test_%s_propagation', char(tlims(1), 'yyyyMMdd_HHmmss'));
outfolder = fullfile(superfolder, 'localisation', name);
if ~isfolder(outfolder), mkdir(outfolder); end

%% The propagation: the ray traced table of the cast and a straight line
% at the same sound speed
tablefile = fullfile(superfolder, 'propagation', [castname '_propagation.mat']);
if ~isfile(tablefile)
    error('No propagation table %s - run propagation/make_propagation_tables.m first.', tablefile);
end
S = load(tablefile);
props.raytrace = S.propagation;
props.straight = straight_propagation(S.propagation.time, S.propagation.soundspeed);
runs = {'straight', 'raytrace'};
runlabels = {sprintf('straight line, %.1f m/s', props.straight.soundspeed), ...
    sprintf('ray traced, %s', castname)};

%% Localise the event both ways
resultsfile = fullfile(outfolder, [name '.mat']);
dorun = relocalise || ~isfile(resultsfile);
if ~dorun
    saved = load(resultsfile);
    dorun = ~isequal(saved.tlims, tlims) || ~isequal(saved.castname, castname) || ...
        ~isequal(saved.minslant, minslant);
end
if dorun
    data = cell(1, numel(landers));
    for i = 1:numel(landers)
        [startTime, ~, serialnumber] = getlanderdeploymentinfo(landers(i), deployment, country);
        data{i} = getlanderpaths(serialnumber, startTime);
    end
    for r = 1:numel(runs)
        rng(seed);
        t0 = tic;
        [res.(runs{r}).loctracks, res.(runs{r}).info] = localiseporpoises(data, arrayfile, ...
            'tlims', tlims, 'outfolder', fullfile(outfolder, runs{r}), 'nruns', nruns, ...
            'particles', particles, 'minslant', minslant, 'propagation', props.(runs{r}));
        fprintf('%s: %.0f s\n', runs{r}, toc(t0));
    end
    save(resultsfile, 'res', 'tlims', 'castname', 'minslant', 'landers');
else
    res = saved.res;
    fprintf('Loaded the localisations from %s\n', resultsfile);
end

info = res.straight.info;
landerxyz = info.settings.landerxyz;
meshdata = info.meshdata;
middle = mean(landerxyz(:,1:2), 1);
t0 = datenum(tlims(1));
cols = [0.15 0.35 0.75; 0.85 0.25 0.1];
eventstr = sprintf('%s landers %s, %s to %s', country, num2str(landers), ...
    char(tlims(1), 'yyyy-MM-dd HH:mm:ss'), char(tlims(2), 'HH:mm:ss'));

% every point of every track of each run: time (s from t0), x, y, z
for r = 1:numel(runs)
    L = res.(runs{r}).loctracks;
    pts = zeros(0, 5);
    for i = 1:numel(L)
        t = (L(i).datestart - t0)*86400 + L(i).loctracktimes(:);
        pts = [pts; t, L(i).xh(1:3,:)', repmat(i, numel(t), 1)]; %#ok<AGROW>
    end
    P.(runs{r}) = pts;
    fprintf('%s: %d fragments, %d points\n', runlabels{r}, numel(L), size(pts, 1));
end

%% 1. Both sets of tracks: plan view and side views
fig1 = figure('Position', [50, 50, 1600, 900], 'Color', 'w');
tl = tiledlayout(2, 2, 'TileSpacing', 'compact');
views = {[1 2], [1 3], [2 3]};
tiles = {{1, [2 1]}, {2}, {4}};
titles = {'Plan view', 'Side view, looking north (x-z)', 'Side view, looking west (y-z)'};
xyzlab = {'East (m)', 'North (m)', 'Height above the sea surface (m)'};
lims = 0;
for r = 1:numel(runs)
    lims = max(lims, max(abs(P.(runs{r})(:,2:3) - middle), [], 'all'));
end
lims = min(500, 25*ceil(1.1*lims/25));
h = gobjects(1, numel(runs));
for v = 1:3
    ax = nexttile(tl, tiles{v}{:}); hold(ax, 'on');
    for r = 1:numel(runs)
        pts = P.(runs{r});
        for i = unique(pts(:,5))'
            in = pts(:,5) == i;
            h(r) = plot(ax, pts(in, 1 + views{v}(1)), pts(in, 1 + views{v}(2)), '.-', ...
                'Color', cols(r,:), 'MarkerSize', 8);
        end
    end
    hl = plot(ax, landerxyz(:,views{v}(1)), landerxyz(:,views{v}(2)), 'k^', ...
        'MarkerFaceColor', 'y', 'MarkerSize', 10);
    if v == 1
        th = linspace(0, 2*pi, 200);
        plot(ax, middle(1) + maxrange*cos(th), middle(2) + maxrange*sin(th), 'k--');
        axis(ax, 'equal'); xlim(ax, middle(1) + [-1 1]*lims); ylim(ax, middle(2) + [-1 1]*lims);
    else
        xlim(ax, middle(views{v}(1)) + [-1 1]*lims);
        ylim(ax, [min(meshdata.z(:)) - 1, 1]);
        yline(ax, 0, 'b-'); yline(ax, min(meshdata.z(:)), 'Color', [0.5 0.4 0.3], 'LineWidth', 2);
    end
    xlabel(ax, xyzlab{views{v}(1)}); ylabel(ax, xyzlab{views{v}(2)});
    title(ax, titles{v}); grid(ax, 'on'); box(ax, 'on'); set(ax, 'FontSize', 13);
end
lgd = legend([h, hl], [runlabels, {'landers'}], 'FontSize', 12, 'NumColumns', 3);
lgd.Layout.Tile = 'south';
title(tl, eventstr, 'FontSize', 14);
save_figure(fig1, outfolder, [name '_tracks']);

%% 2. Depth and range against time
fig2 = figure('Position', [50, 50, 1300, 700], 'Color', 'w');
tl = tiledlayout(2, 1, 'TileSpacing', 'compact');
ax1 = nexttile(tl); hold(ax1, 'on');
ax2 = nexttile(tl); hold(ax2, 'on');
for r = 1:numel(runs)
    pts = P.(runs{r});
    for i = unique(pts(:,5))'
        in = pts(:,5) == i;
        h(r) = plot(ax1, pts(in,1), -pts(in,4), '.-', 'Color', cols(r,:));
        plot(ax2, pts(in,1), hypot(pts(in,2) - middle(1), pts(in,3) - middle(2)), '.-', 'Color', cols(r,:));
    end
end
set(ax1, 'YDir', 'reverse'); ylim(ax1, [-0.5, -min(meshdata.z(:)) + 0.5]);
yline(ax1, -min(meshdata.z(:)), 'Color', [0.5 0.4 0.3], 'LineWidth', 2);
ylabel(ax1, 'Depth (m)'); grid(ax1, 'on'); box(ax1, 'on');
legend(ax1, h, runlabels, 'Location', 'southwest');
ylabel(ax2, 'Range from the middle of the array (m)'); xlabel(ax2, 'Time from the start (s)');
yline(ax2, maxrange, 'k--'); grid(ax2, 'on'); box(ax2, 'on');
title(tl, eventstr, 'FontSize', 13);
save_figure(fig2, outfolder, [name '_depth_range']);

%% 3. Change in depth with range
% the ray traced position at the times of the straight line track, where
% the two runs have a track at the same time
s = P.straight; q = P.raytrace;
dz = nan(size(s, 1), 1); dh = dz;
for i = unique(q(:,5))'
    in = q(:,5) == i;
    [tq, u] = unique(q(in,1)); qq = q(in,:); qq = qq(u,:);
    if numel(tq) < 2, continue; end
    k = s(:,1) >= tq(1) & s(:,1) <= tq(end) & isnan(dz);
    zq = interp1(tq, qq(:,4), s(k,1));
    xq = interp1(tq, qq(:,2:3), s(k,1));
    dz(k) = -(zq - s(k,4));                       % depth change, + deeper
    dh(k) = vecnorm(xq - s(k,2:3), 2, 2);         % horizontal shift
end
rs = hypot(s(:,2) - middle(1), s(:,3) - middle(2));
fig3 = figure('Position', [50, 50, 1300, 500], 'Color', 'w');
tl = tiledlayout(1, 2, 'TileSpacing', 'compact');
ax = nexttile(tl);
scatter(ax, rs, dz, 15, s(:,1), 'filled'); colormap(ax, 'jet'); cb = colorbar(ax); cb.Label.String = 'time (s)';
yline(ax, 0, 'k'); grid(ax, 'on'); box(ax, 'on');
xlabel(ax, 'Range from the middle of the array, straight line (m)');
ylabel(ax, 'Depth change, ray traced - straight line (m, + deeper)');
title(ax, 'Depth');
ax = nexttile(tl);
scatter(ax, rs, dh, 15, s(:,1), 'filled'); colormap(ax, 'jet');
grid(ax, 'on'); box(ax, 'on');
xlabel(ax, 'Range from the middle of the array, straight line (m)');
ylabel(ax, 'Horizontal shift (m)'); title(ax, 'Horizontal position');
title(tl, {eventstr, runlabels{2}}, 'FontSize', 13, 'Interpreter', 'none');
save_figure(fig3, outfolder, [name '_change']);

%% Summary
bands = [0 50; 50 100; 100 150; 150 inf];
fprintf('\nRay traced - straight line, at the times of the straight line track:\n');
for b = 1:size(bands, 1)
    in = rs >= bands(b,1) & rs < bands(b,2) & ~isnan(dz);
    fprintf('  %3g-%3g m: %4d points, depth change median %+5.1f m (IQR %+5.1f to %+5.1f), horizontal shift median %4.1f m\n', ...
        bands(b,1), bands(b,2), sum(in), median(dz(in)), prctile(dz(in), 25), prctile(dz(in), 75), median(dh(in)));
end
for r = 1:numel(runs)
    pts = P.(runs{r});
    d = -pts(:,4);
    fprintf('%s: depth median %.1f m, %.0f%% of points within 0.5 m of the surface\n', runlabels{r}, ...
        median(d), 100*mean(d < 0.5));
end

%% ------------------------------------------------------------------------
function save_figure(fig, outfolder, name)
exportgraphics(fig, fullfile(outfolder, [name '.png']), 'Resolution', 150);
savefig(fig, fullfile(outfolder, [name '.fig']));
fprintf('Saved %s\n', fullfile(outfolder, [name '.png']));
end
