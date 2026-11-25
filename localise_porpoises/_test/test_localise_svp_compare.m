%% Test: how much the sound speed profile changes one localised event
%
% An illustrative example, not a full assessment. The same period as
% TEST_LOCALISE_ONE_EVENT is localised three ways with LOCALISEPORPOISES:
%   1. straight lines at SOUNDSPEED
%   2. ray traced through the best case cast: 25 June 2025, well mixed
%      (sound speed varies by ~1 m/s top to bottom)
%   3. ray traced through the worst case cast: 12 Sept 2025, thermocline at
%      10-14 m (sound speed falls 11 m/s from 1488 to 1476 m/s)
% Neither cast is from deployment 1 (Oct 2024): they bracket what the
% water column might have been. Only the predicted time delays differ
% between the runs, and the random numbers are reset before each one.
%
% Plots (in OUTFOLDER):
%   1. the two profiles and the direct path rays from a lander hydrophone
%      through each, with the slant angle bias (ray traced - straight)
%   2. the tracks of all three runs: plan view and two side views
%   3. depth and range from the middle of the array against time
%   4. depth against range, and the change in depth and horizontal position
%      from the straight line track
%
% The tables are made by propagation/make_propagation_tables.m.
%
% Needs the CUMBIAH library, soundnet, PAMGUARD, the CIBBRiNA soundtrap_4c
% code, the particle filter and ACTUP (for the ray plot) on the MATLAB path.
clear
close all

%% Inputs
country    = 'Denmark';
deployment = 1;
landers    = [1 2 3];
tlims = [datetime(2024, 10, 20, 15, 46, 0), datetime(2024, 10, 20, 15, 50, 30)];

soundspeed = 1482;      % straight line sound speed (m/s)
casts = {'CC2043006_20250625_141044', 'CC2043006_20250912_092555'}; % best and worst case
relocalise = false;     % run the particle filter again even if the results are saved
minslant = -10;
nruns = 5;
particles = 1000;
likelihood = 'inverse';
maxrange = 150;         % circle around the array (m)
seed = 1;

%% Paths
here = fileparts(mfilename('fullpath'));
folders = strsplit(genpath(fileparts(fileparts(here))), pathsep);
[~, names] = cellfun(@fileparts, folders, 'UniformOutput', false);
folders = folders(~ismember(names, {'_old', '_test', '_tests', ''}) & ~contains(folders, [filesep '.']));
addpath(strjoin(folders, pathsep));

superfolder = getlandersuperfolder(country);
arrayfile = fullfile(superfolder, sprintf('lander_array_locations_dep%d.mat', deployment));
name = sprintf('test_%s_svp_compare', char(tlims(1), 'yyyyMMdd_HHmmss'));
outfolder = fullfile(superfolder, 'localisation', name);
if ~isfolder(outfolder), mkdir(outfolder); end

%% The three propagation models
runs = {'straight', 'june', 'sept'};
props.straight = straight_propagation(NaT, soundspeed);
for k = 1:2
    S = load(fullfile(superfolder, 'propagation', [casts{k} '_propagation.mat']));
    props.(runs{k+1}) = S.propagation;
end
runlabels = {sprintf('Straight line, %g m/s', soundspeed), ...
    'Ray traced, 25 Jun 2025 (well mixed)', 'Ray traced, 12 Sep 2025 (thermocline)'};
cols = [0.2 0.2 0.2; 0.15 0.45 0.85; 0.85 0.25 0.1];

%% Localise the event three ways
resultsfile = fullfile(outfolder, [name '.mat']);
dorun = relocalise || ~isfile(resultsfile);
if ~dorun
    saved = load(resultsfile);
    dorun = ~isequal(saved.tlims, tlims) || ~isequal(saved.casts, casts) || ...
        ~isequal(saved.soundspeed, soundspeed) || ~isequal(saved.minslant, minslant);
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
            'particles', particles, 'minslant', minslant, 'soundspeed', soundspeed, ...
            'propagation', props.(runs{r}), 'likelihood', likelihood, 'savefigs', false);
        fprintf('%s: %.0f s\n', runs{r}, toc(t0));
    end
    save(resultsfile, 'res', 'tlims', 'casts', 'soundspeed', 'minslant', 'landers');
else
    res = saved.res;
    fprintf('Loaded the localisations from %s\n', resultsfile);
end

info = res.straight.info;
landerxyz = info.settings.landerxyz;
meshdata = info.meshdata;
seabed = -min(meshdata.z(:));
middle = mean(landerxyz(:,1:2), 1);
t0 = datenum(tlims(1));
eventstr = sprintf('%s landers %s, %s to %s', country, num2str(landers), ...
    char(tlims(1), 'yyyy-MM-dd HH:mm:ss'), char(tlims(2), 'HH:mm:ss'));

% every point of every track of each run: time (s from t0), x, y, z, track
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

%% 1. The profiles and the rays
fig1 = figure('Position', [50, 50, 1500, 800], 'Color', 'w');
tl = tiledlayout(2, 4, 'TileSpacing', 'compact');
angles = -(0:1:25);          % launch angles (deg, + down): rays going up to the porpoise
for k = 1:2
    Q = props.(runs{k+1});
    ax = nexttile(tl, 4*(k-1) + 1);
    plot(ax, Q.c, Q.z, '-', 'Color', cols(k+1,:), 'LineWidth', 2);
    set(ax, 'YDir', 'reverse'); ylim(ax, [0 Q.seabed]); xlim(ax, [1468 1492]);
    yline(ax, Q.hdepth, 'k--'); grid(ax, 'on'); box(ax, 'on');
    xlabel(ax, 'Sound speed (m/s)'); ylabel(ax, 'Depth (m)'); title(ax, runlabels{k+1});

    % the slant bias behind the rays: the elevation a click really arrives
    % from minus the straight line elevation
    ax = nexttile(tl, 4*(k-1) + 2, [1 3]); hold(ax, 'on');
    [R, D] = ndgrid(Q.ranges, Q.depths);
    bias = Q.slant - atan2d(Q.hdepth - D, R);
    bias(Q.shadow) = NaN;
    imagesc(ax, Q.ranges, Q.depths, bias', 'AlphaData', ~isnan(bias'));
    colormap(ax, interp1([0 0.5 1], [0.13 0.40 0.75; 0.97 0.97 0.97; 0.80 0.25 0.15], linspace(0, 1, 256)));
    clim(ax, [-6 6]); cb = colorbar(ax); cb.Label.String = 'Slant bias, ray - straight (deg)';
    rays = actup_trace_rays(Q.z, Q.c, Q.hdepth, angles, 'maxrange', 250, 'directonly', true);
    for i = 1:numel(rays)
        direct = rays(i).nbnc == 0;
        plot(ax, rays(i).r(direct), rays(i).z(direct), 'k-', 'LineWidth', 0.6);
        % the straight line at the same launch angle
        rr = [0 min(250, Q.hdepth/tand(max(-angles(i), 0.01)))];
        plot(ax, rr, Q.hdepth - rr*tand(-angles(i)), ':', 'Color', [0.5 0.5 0.5]);
    end
    xline(ax, maxrange, 'k--');
    set(ax, 'YDir', 'reverse'); xlim(ax, [0 250]); ylim(ax, [0 Q.seabed]);
    xlabel(ax, 'Range from the lander (m)'); ylabel(ax, 'Depth (m)'); box(ax, 'on');
    title(ax, sprintf('Direct rays at 0-25%s elevation (solid) and straight lines (dotted)', char(176)));
    set(ax, 'Layer', 'top');
end
title(tl, {'Best and worst case sound speed profiles at the Danish array', ...
    'BELLHOP (ACTUP) geometric ray trace at 130 kHz (ACTUP_TRACE_RAYS default; ray paths do not depend on frequency)'}, 'FontSize', 14);
save_figure(fig1, outfolder, [name '_rays']);

%% 2. The tracks: plan view and side views
fig2 = figure('Position', [50, 50, 1600, 900], 'Color', 'w');
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
        xlim(ax, middle(views{v}(1)) + [-1 1]*lims); ylim(ax, [-seabed - 1, 1]);
        yline(ax, 0, 'b-'); yline(ax, -seabed, 'Color', [0.5 0.4 0.3], 'LineWidth', 2);
    end
    xlabel(ax, xyzlab{views{v}(1)}); ylabel(ax, xyzlab{views{v}(2)});
    title(ax, titles{v}); grid(ax, 'on'); box(ax, 'on'); set(ax, 'FontSize', 13);
end
lgd = legend([h, hl], [runlabels, {'landers'}], 'FontSize', 12, 'NumColumns', 4);
lgd.Layout.Tile = 'south';
title(tl, eventstr, 'FontSize', 14);
save_figure(fig2, outfolder, [name '_tracks']);

%% 3. Depth and range against time
fig3 = figure('Position', [50, 50, 1300, 700], 'Color', 'w');
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
set(ax1, 'YDir', 'reverse'); ylim(ax1, [-0.5, seabed + 0.5]);
yline(ax1, seabed, 'Color', [0.5 0.4 0.3], 'LineWidth', 2);
ylabel(ax1, 'Depth (m)'); grid(ax1, 'on'); box(ax1, 'on');
legend(ax1, h, runlabels, 'Location', 'southwest');
ylabel(ax2, 'Range from the middle of the array (m)'); xlabel(ax2, 'Time from the start (s)');
yline(ax2, maxrange, 'k--'); grid(ax2, 'on'); box(ax2, 'on');
title(tl, eventstr, 'FontSize', 13);
save_figure(fig3, outfolder, [name '_depth_range']);

%% 4. Depth against range, and the change from the straight line track
s = P.straight;
rs = hypot(s(:,2) - middle(1), s(:,3) - middle(2));
fig4 = figure('Position', [50, 50, 1600, 500], 'Color', 'w');
tl = tiledlayout(1, 3, 'TileSpacing', 'compact');
ax1 = nexttile(tl); hold(ax1, 'on');
ax2 = nexttile(tl); hold(ax2, 'on');
ax3 = nexttile(tl); hold(ax3, 'on');
for r = 1:numel(runs)
    q = P.(runs{r});
    h(r) = plot(ax1, hypot(q(:,2) - middle(1), q(:,3) - middle(2)), -q(:,4), '.', 'Color', cols(r,:));
end
bands = [0 50; 50 100; 100 150; 150 inf];
fprintf('\nChange from the straight line track, at its times:\n');
for r = 2:numel(runs)
    [dz, dh] = change_from(s, P.(runs{r}));
    plot(ax2, rs, dz, '.', 'Color', cols(r,:));
    plot(ax3, rs, dh, '.', 'Color', cols(r,:));
    fprintf('%s\n', runlabels{r});
    for b = 1:size(bands, 1)
        in = rs >= bands(b,1) & rs < bands(b,2) & ~isnan(dz);
        fprintf('  %3g-%3g m: %4d points, depth change median %+5.1f m (IQR %+5.1f to %+5.1f), horizontal shift median %4.1f m\n', ...
            bands(b,1), bands(b,2), sum(in), median(dz(in)), prctile(dz(in), 25), prctile(dz(in), 75), median(dh(in)));
    end
end
set(ax1, 'YDir', 'reverse'); ylim(ax1, [-0.5, seabed + 0.5]);
xlabel(ax1, 'Range from the middle of the array (m)'); ylabel(ax1, 'Depth (m)');
title(ax1, 'Depth against range'); legend(ax1, h, runlabels, 'Location', 'southwest', 'AutoUpdate', 'off');
yline(ax2, 0, 'k');
xlabel(ax2, 'Range, straight line track (m)'); ylabel(ax2, 'Depth change from straight line (m, + deeper)');
title(ax2, 'Depth change');
xlabel(ax3, 'Range, straight line track (m)'); ylabel(ax3, 'Horizontal shift from straight line (m)');
title(ax3, 'Horizontal shift');
for ax = [ax1 ax2 ax3], grid(ax, 'on'); box(ax, 'on'); xline(ax, maxrange, 'k--'); set(ax, 'FontSize', 12); end
title(tl, eventstr, 'FontSize', 13);
save_figure(fig4, outfolder, [name '_change']);

for r = 1:numel(runs)
    d = -P.(runs{r})(:,4);
    fprintf('%s: depth median %.1f m, %.0f%% of points within 0.5 m of the surface\n', ...
        runlabels{r}, median(d), 100*mean(d < 0.5));
end

%% ------------------------------------------------------------------------
function [dz, dh] = change_from(s, q)
% depth change (+ deeper) and horizontal shift of track points Q from the
% straight line points S, at the times of S where Q has a track
dz = nan(size(s, 1), 1); dh = dz;
for i = unique(q(:,5))'
    in = q(:,5) == i;
    [tq, u] = unique(q(in,1)); qq = q(in,:); qq = qq(u,:);
    if numel(tq) < 2, continue; end
    k = s(:,1) >= tq(1) & s(:,1) <= tq(end) & isnan(dz);
    dz(k) = -(interp1(tq, qq(:,4), s(k,1)) - s(k,4));
    dh(k) = vecnorm(interp1(tq, qq(:,2:3), s(k,1)) - s(k,2:3), 2, 2);
end
end

function save_figure(fig, outfolder, name)
exportgraphics(fig, fullfile(outfolder, [name '.png']), 'Resolution', 150);
savefig(fig, fullfile(outfolder, [name '.fig']));
fprintf('Saved %s\n', fullfile(outfolder, [name '.png']));
end
