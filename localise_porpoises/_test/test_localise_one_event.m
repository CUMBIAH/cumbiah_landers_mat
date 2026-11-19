%% Test: localise one event on a lander array and make diagnostic plots and a movie
%
% Runs LOCALISEPORPOISES on the tracks of a single period (TLIMS) of an
% array of landers, then plots:
%   1. the landers of the array over the seabed, as LOCATE_ARRAY does but
%      without the drop positions (PLOT_LANDER_ARRAY)
%   2. every localised track of the period over the seabed, coloured by
%      time from the start of the period (PLOT_LOCTRACK_ARRAY), in 3D and
%      as a plan view (xy) beside two side views (xz and yz)
%   3. the bearing and slant angle of every click each lander heard against
%      those from the lander to the localised track (PLOT_LOCTRACK_BEARINGS)
%   4. the range of the track from each lander against time, with error
%      bars from the spread of the particle filter (PLOT_LOCTRACK_RANGE)
% and makes a movie of the tracks building up through the period, with the
% true bearings of the clicks from each lander, in a plan view (xy) beside
% two side views (xz and yz), with all the animals on the same axes
% (PLOT_LOCTRACK_FRAME).
%
% Run locate_array.m (positions and orientations of the landers) and
% cumbiah_multitrack.m on each lander (the bearing tracks) first.
%
% Only this period is read, so the clocks are found from its clicks alone
% (one comb filter search within MAXOFFSET of 0) and the array encounters
% are numbered from 1 within it - the PA codes are not those of a whole
% deployment run. The localisation is kept in OUTFOLDER and only run again
% when RELOCALISE is true or the time limits change.
%
% Needs the CUMBIAH library, soundnet, PAMGUARD, the CIBBRiNA soundtrap_4c
% code and the particle filter on the MATLAB path.
clear
close all

%% Inputs
country    = 'Denmark';
deployment = 1;
landers    = [1 2 3];   % the landers of the array; the first is the reference clock

% the event: one porpoise, though the tracker splits it in two for a while
tlims = [datetime(2024, 10, 20, 15, 46, 0), datetime(2024, 10, 20, 15, 50, 30)];

relocalise = false;     % run the particle filter again even if the results are saved

% clicks with a true slant angle below this (deg) are left out - the
% landers are on the seabed, so nothing can be heard from below them
minslant = -10;

soundspeed = 1482;      % speed of sound (m/s) of straight line propagation

% ray traced propagation through the CTD casts at the array
% (propagation/make_propagation_tables.m), so refraction is allowed for.
% There is no cast from deployment 1 (Oct 2024), so the cast closest in
% time of year ('season') is used, whatever the year. raytrace = false for
% straight lines at SOUNDSPEED
raytrace = true;
propagationmatch = 'season';  % 'season' (time of year) or 'time' (date)

% particle filter (porpoise)
nruns = 5;              % runs of the particle filter
particles = 1000;       % particles in each run

% the movie
makemovie = true;
framestep = 1;          % time between frames (s)
framerate = 10;         % frames per second of the movie
bearingwindow = 2;      % bearings of the clicks of this many s before each frame (s)

% a circle this far around the middle of the array (m); the points of the
% tracks outside it are grey. [] for none
maxrange = 150;

%% Paths
% the CUMBIAH library (this repository) with the plot functions of the
% localisation, but not the _test folders
here = fileparts(mfilename('fullpath'));
folders = strsplit(genpath(fileparts(fileparts(here))), pathsep);
[~, names] = cellfun(@fileparts, folders, 'UniformOutput', false);
folders = folders(~ismember(names, {'_old', '_test', '_tests', ''}) & ~contains(folders, [filesep '.']));
addpath(strjoin(folders, pathsep));

% the positions and orientations of the landers, saved by locate_array.m
arrayfile = fullfile(getlandersuperfolder(country), ...
    sprintf('lander_array_locations_dep%d.mat', deployment));
name = sprintf('test_%s', char(tlims(1), 'yyyyMMdd_HHmmss'));
outfolder = fullfile(getlandersuperfolder(country), 'localisation', name);

%% Localise the event
resultsfile = fullfile(outfolder, [name '_test.mat']);
dorun = relocalise || ~isfile(resultsfile);
if ~dorun
    saved = load(resultsfile);
    dorun = ~isequal(saved.tlims, tlims) || ~isequal(saved.landers, landers) || ...
        ~isfield(saved, 'minslant') || ~isequal(saved.minslant, minslant) || ...
        ~isfield(saved, 'soundspeed') || ~isequal(saved.soundspeed, soundspeed) || ...
        ~isfield(saved, 'raytrace') || ~isequal(saved.raytrace, raytrace) || ...
        ~isequal(saved.propagationmatch, propagationmatch);
end
if dorun
    % one deployment record for each lander of the array
    data = cell(1, numel(landers));
    for i = 1:numel(landers)
        [startTime, ~, serialnumber] = getlanderdeploymentinfo(landers(i), deployment, country);
        data{i} = getlanderpaths(serialnumber, startTime);
    end
    propagation = [];
    if raytrace
        S = load(fullfile(getlandersuperfolder(country), 'propagation', 'propagation_tables.mat'));
        propagation = S.propagation;
    end
    [loctracks, info] = localiseporpoises(data, arrayfile, 'tlims', tlims, 'outfolder', outfolder, ...
        'nruns', nruns, 'particles', particles, 'minslant', minslant, ...
        'soundspeed', soundspeed, 'propagation', propagation, 'propagationmatch', propagationmatch);
    save(resultsfile, 'loctracks', 'info', 'tlims', 'landers', 'minslant', 'soundspeed', ...
        'raytrace', 'propagationmatch');
else
    loctracks = saved.loctracks;
    info = saved.info;
    fprintf('Loaded the localisation from %s\n', resultsfile);
end
if isempty(loctracks)
    fprintf('Nothing was localised between %s and %s\n', char(tlims(1)), char(tlims(2)));
    return
end
fprintf('%d track fragments of %d animals: %s\n', numel(loctracks), numel(unique({loctracks.code})), ...
    strjoin(unique({loctracks.code}), ', '));

landerxyz = info.settings.landerxyz;
landernumbers = info.settings.landers;
meshdata = info.meshdata;
t0 = datenum(tlims(1));
tsec = [0 seconds(diff(tlims))];          % colour scale: s from the start of the event
clicks = reference_clock(info.clicks, info.encounters);

% the area plotted: wide enough for the tracks and the landers
xy = [loctracks.xh];
xy = [xy(1:2,:), landerxyz(:,1:2)'];
lims = min(500, max(50, 25*ceil(1.1*max(abs(xy), [], 'all')/25)));
eventstr = sprintf('%s landers %s, %s to %s', country, num2str(landernumbers), ...
    char(tlims(1), 'yyyy-MM-dd HH:mm:ss'), char(tlims(2), 'HH:mm:ss'));
if isfield(loctracks, 'propagation')
    % underscores of the cast name are subscripts to TeX
    eventstr = sprintf('%s (%s)', eventstr, strrep(loctracks(1).propagation, '_', '\_'));
    fprintf('Propagation: %s\n', loctracks(1).propagation);
end

%% 1. The landers
fig1 = figure('Position', [50, 50, 1000, 700]);
plot_lander_array(landerxyz, meshdata, 'landernumbers', landernumbers, 'lims', lims);
view(-30, 45)
title({sprintf('CUMBIAH landers, %s deployment %d', country, deployment), ...
    sprintf('origin %.6f N %.6f E', info.settings.reflatlon)});
set(gca, 'FontSize', 14)
save_figure(fig1, outfolder, [name '_landers']);

%% 2. The tracks, coloured by time
fig2 = figure('Position', [50, 50, 1100, 700]);
plot_loctrack_array(loctracks, landerxyz, meshdata, 't0', t0, 'timelims', tsec, ...
    'landernumbers', landernumbers, 'lims', lims, 'maxrange', maxrange);
view([30, 45])
title(sprintf('%s: %d tracks of %d animals', eventstr, numel(loctracks), ...
    numel(unique({loctracks.code}))));
set(gca, 'FontSize', 14);
save_figure(fig2, outfolder, [name '_loctracks']);

% the same as a plan view (left) and two side views (right): x-z
% looking north and y-z looking west
fig3 = figure('Position', [50, 50, 1600, 900]);
tl = tiledlayout(2, 2, 'TileSpacing', 'compact');
axs = gobjects(1, 3);
axs(1) = nexttile(tl, 1, [2 1]);
plot_loctrack_array(loctracks, landerxyz, meshdata, 't0', t0, 'timelims', tsec, ...
    'landernumbers', landernumbers, 'lims', lims, 'showlegend', true, 'maxrange', maxrange);
plan_view(axs(1), lims, 'Plan view');
axs(2) = nexttile(tl, 2);
plot_loctrack_array(loctracks, landerxyz, meshdata, 't0', t0, 'timelims', tsec, ...
    'landernumbers', landernumbers, 'lims', lims, 'showlegend', false, 'showcolorbar', false, ...
    'maxrange', maxrange);
side_view(axs(2), [0 0], meshdata, 'Side view, looking north (x-z)');
axs(3) = nexttile(tl, 4);
plot_loctrack_array(loctracks, landerxyz, meshdata, 't0', t0, 'timelims', tsec, ...
    'landernumbers', landernumbers, 'lims', lims, 'showlegend', false, 'showcolorbar', false, ...
    'maxrange', maxrange);
side_view(axs(3), [90 0], meshdata, 'Side view, looking west (y-z)');
% the time colour map of the tracks of one axes spills over onto the
% seabed of the others
for ax = axs, colormap(ax, 'bone'); end
% the legend in a row underneath all the plots
lgd = legend(axs(1));
lgd.Layout.Tile = 'south';
lgd.NumColumns = 5;
lgd.FontSize = 12;
title(tl, eventstr, 'FontSize', 14);
save_figure(fig3, outfolder, [name '_loctracks_xy_xz_yz']);

%% 3. The bearings each lander heard against the tracks
fig4 = figure('Position', [50, 50, 1300, 250*numel(landernumbers) + 100]);
plot_loctrack_bearings(loctracks, landerxyz, clicks, 't0', t0, 'timelims', tsec, ...
    'landernumbers', landernumbers);
sgtitle({eventstr, 'grey: true bearings of the clicks; colour: from the lander to the localised track'}, ...
    'FontSize', 12);
save_figure(fig4, outfolder, [name '_bearings']);

%% 4. The range from each lander, with the spread of the particle filter
fig6 = figure('Position', [50, 50, 1100, 250*numel(landernumbers) + 100]);
plot_loctrack_range(loctracks, landerxyz, 't0', t0, 'timelims', tsec, ...
    'landernumbers', landernumbers, 'maxrange', maxrange);
sgtitle({eventstr, 'range from each lander, +/- 1 st dev of the particles'}, 'FontSize', 12);
save_figure(fig6, outfolder, [name '_range']);

%% 5. The movie
if makemovie
    moviefile = fullfile(outfolder, [name '_movie.mp4']);
    vw = VideoWriter(moviefile, 'MPEG-4');
    vw.FrameRate = framerate;
    vw.Quality = 90;
    open(vw);
    frames = t0 + (framestep:framestep:tsec(2))/86400;
    fig5 = figure('Position', [50, 50, 1600, 900], 'Color', 'w');
    cols = getdefaultcols();
    frameargs = {'t0', t0, 'timelims', tsec, 'bearingwindow', bearingwindow, 'lims', lims, ...
        'landernumbers', landernumbers, 'maxrange', maxrange};
    for f = 1:numel(frames)
        clf(fig5)
        tl = tiledlayout(fig5, 2, 2, 'TileSpacing', 'compact');

        % plan view on the left, with the time colour bar
        ax1 = nexttile(tl, 1, [2 1]);
        [htrack, hl, ~, ~, hout, hcircle] = plot_loctrack_frame(loctracks, landerxyz, meshdata, clicks, frames(f), frameargs{:});
        plan_view(ax1, lims, 'Plan view');

        % side views on the right: x-z looking north and y-z looking west
        ax2 = nexttile(tl, 2);
        plot_loctrack_frame(loctracks, landerxyz, meshdata, clicks, frames(f), frameargs{:}, ...
            'showcolorbar', false);
        side_view(ax2, [0 0], meshdata, 'Side view, looking north (x-z)');
        ax3 = nexttile(tl, 4);
        plot_loctrack_frame(loctracks, landerxyz, meshdata, clicks, frames(f), frameargs{:}, ...
            'showcolorbar', false);
        side_view(ax3, [90 0], meshdata, 'Side view, looking west (y-z)');

        % the time colour map of the tracks of one axes spills over onto
        % the seabed of the others
        for ax = [ax1 ax2 ax3], colormap(ax, 'bone'); end

        % a legend which does not change from frame to frame
        hold(ax1, 'on')
        hkey = gobjects(1, numel(landernumbers));
        for d = 1:numel(landernumbers)
            hkey(d) = plot(ax1, NaN, NaN, 'Color', cols(d,:), 'LineWidth', 1.5);
        end
        hpos = plot(ax1, NaN, NaN, 'p', 'MarkerSize', 12, 'MarkerFaceColor', 'y', 'MarkerEdgeColor', 'k');
        hold(ax1, 'off')
        keys = [hl(1:numel(landernumbers)), hkey, hpos];
        labels = [arrayfun(@(n) sprintf('Lander %d', n), landernumbers, 'UniformOutput', false), ...
            arrayfun(@(n) sprintf('Bearings, lander %d', n), landernumbers, 'UniformOutput', false), ...
            {'Porpoise now'}];
        if ~isempty(hcircle)
            keys = [hcircle, keys]; %#ok<AGROW>
            labels = [{sprintf('%g m from the array', maxrange)}, labels]; %#ok<AGROW>
        end
        if ~isempty(hout)
            keys = [hout, keys]; %#ok<AGROW>
            labels = [{sprintf('Track beyond %g m', maxrange)}, labels]; %#ok<AGROW>
        end
        if ~isempty(htrack)
            keys = [htrack(1), keys]; %#ok<AGROW>
            labels = [{'Porpoise track'}, labels]; %#ok<AGROW>
        end
        % in a row underneath all the plots
        lgd = legend(ax1, keys, labels, 'FontSize', 11, 'NumColumns', 6);
        lgd.Layout.Tile = 'south';

        title(tl, sprintf('%s   %s (%.0f s)', eventstr, datestr(frames(f), 'HH:MM:SS'), ...
            (frames(f) - t0)*86400), 'FontSize', 14);
        drawnow
        writeVideo(vw, getframe(fig5));
        if mod(f, 30) == 0
            fprintf('Frame %d of %d\n', f, numel(frames));
        end
    end
    close(vw);
    fprintf('Saved %s\n', moviefile);
end

%% ------------------------------------------------------------------------
function clicks = reference_clock(clicks, encounters)
% the click times of each lander put on the reference lander's clock with
% the clock offset of the encounter they are in (the nearest encounter for
% clicks outside every encounter)
if isempty(encounters)
    return
end
tlim = vertcat(encounters.tlims);
offset = vertcat(encounters.clockoffset);
for d = 1:numel(clicks)
    t = clicks(d).t;
    outside = max(0, max(tlim(:,1)' - t, t - tlim(:,2)')); % time outside each encounter
    [~, k] = min(outside, [], 2);
    clicks(d).t = t - offset(k, d)/86400;
end
end

function plan_view(ax, lims, titlestr)
% a plan view of the tracks, x and y to the same scale
view(ax, 2)
axis(ax, 'equal')
xlim(ax, [-1 1]*lims); ylim(ax, [-1 1]*lims)
title(ax, titlestr)
set(ax, 'FontSize', 13)
end

function side_view(ax, az, meshdata, titlestr)
% a side view of the tracks from the sea surface to the seabed
view(ax, az)
zlim(ax, [min(meshdata.z(:)) - 1, 1])
title(ax, titlestr)
set(ax, 'FontSize', 13)
end

function save_figure(fig, outfolder, name)
exportgraphics(fig, fullfile(outfolder, [name '.png']), 'Resolution', 150);
savefig(fig, fullfile(outfolder, [name '.fig']));
fprintf('Saved %s\n', fullfile(outfolder, [name '.png']));
end
