%% Test: localise the tracks of one encounter of one lander
%
% Takes a single encounter of CUMBIAH_MULTITRACK on one lander (EVENTCODE,
% e.g. PP1007 on lander 1), reads its time limits from that lander's
% ..._porpoise.sqlite3 database and runs LOCALISEPORPOISES on just that
% period: the tracks of every lander of the array inside the limits are
% matched, time aligned and localised, and the tracks are plotted over the
% bathymetry coloured by time. A quick way to try settings on one event
% before a whole deployment is run.
%
% Only this period is read, so:
%   - the clocks are found from the clicks of this period alone (one comb
%     filter search within MAXOFFSET of 0, no clock line through the
%     deployment). Late in a long deployment raise MAXOFFSET, or give the
%     offsets of a full run with 'clockprior'.
%   - the array encounters are numbered from 1 within the period, so the
%     PA codes here are not those of a run of the whole deployment.
%
% The results go to their own folder, <lander super folder>/localisation/
% test_<EVENTCODE>_lander<N>, so they do not mix with a full run.
%
% Needs the CUMBIAH library, soundnet, PAMGUARD and the CIBBRiNA
% soundtrap_4c code on the MATLAB path.
clear
close all

%% Inputs
country    = 'Denmark';
deployment = 1;
landers    = [1 2 3];   % the landers of the array

eventlander = 1;        % the lander the event is on
eventcode   = 'PP1007'; % the encounter of CUMBIAH_MULTITRACK on that lander
pad         = 5;        % time added either side of the event (s)

% the positions and orientations of the landers, saved by locate_array.m
arrayfile = fullfile(getlandersuperfolder(country), ...
    sprintf('lander_array_locations_dep%d.mat', deployment));
outfolder = fullfile(getlandersuperfolder(country), 'localisation', ...
    sprintf('test_%s_lander%d', eventcode, eventlander));

% particle filter (porpoise)
nruns = 5;              % the number of runs for the particle filter
particles = 1000;       % particles in each run

%% Paths
% the particle filter and time delay code are not on the startup path
root = fullfile(matlabdrive, 'MATLAB');
folders = strsplit(genpath(fullfile(root, 'localisation')), pathsep);
[~, names] = cellfun(@fileparts, folders, 'UniformOutput', false);
folders = folders(~ismember(names, {'_old', '_test', '_tests', ''}));
addpath(strjoin([folders, {fullfile(root, 'sim_sounds', 'sim_utils')}], pathsep));

%% The landers
% one deployment record for each lander of the array. The lander of the
% event goes first, so every time is on its clock, as the event's are.
landers = [eventlander, setdiff(landers, eventlander, 'stable')];
data = cell(1, numel(landers));
for i = 1:numel(landers)
    [startTime, ~, serialnumber] = getlanderdeploymentinfo(landers(i), deployment, country);
    data{i} = getlanderpaths(serialnumber, startTime);
end

%% Time limits of the event
% from the tracks of the encounter in the lander's database: the event
% comments which start with the code, e.g. PP1007AA01, PP1007AB01, ...
conn = sqlite(data{1}.porpoisedB, 'readonly');
ev = fetch(conn, sprintf(['select UTC, EventEnd from Click_Detector_OfflineEvents ' ...
    'where comment like ''%s%%'''], eventcode));
close(conn);
if isempty(ev)
    error('No tracks with code %s in %s.', eventcode, data{1}.porpoisedB);
end
fmt = 'yyyy-MM-dd HH:mm:ss.SSS';
tlims = [min(datetime(string(ev.UTC), 'InputFormat', fmt)) - seconds(pad), ...
    max(datetime(string(ev.EventEnd), 'InputFormat', fmt)) + seconds(pad)];
fprintf('%s on lander %d: %d tracks, %s to %s\n', eventcode, eventlander, height(ev), ...
    char(tlims(1), 'yyyy-MM-dd HH:mm:ss'), char(tlims(2), 'HH:mm:ss'));

%% Match, time align and localise the tracks of the event
[loctracks, info] = localiseporpoises(data, arrayfile, 'tlims', tlims, 'outfolder', outfolder, ...
    'nruns', nruns, 'particles', particles);

%% Plot the tracks of the event
% all of the tracks together, coloured by time from the start of the event
if isempty(loctracks)
    fprintf('No tracks of %s were localised\n', eventcode);
    return
end
% the time of every track from the start of the event, not of its own
% array encounter, so one colour scale holds them all
t0 = datenum(tlims(1));
plottracks = loctracks;
for i = 1:numel(plottracks)
    plottracks(i).loctracktimes = plottracks(i).loctracktimes + (plottracks(i).datestart - t0)*86400;
    plottracks(i).datestart = t0;
    plottracks(i).dateend = datenum(tlims(2));
end

fig = figure('Position', [0, 0, 1100, 700]);
xy = [loctracks.xh];
lims = min(500, max(100, 50*ceil(prctile(max(abs(xy(1:2,:))), 95)/50)));
plot_loctrack_landers(plottracks, info.settings.landerxyz, info.meshdata, ...
    'landernumbers', info.settings.landers, 'timelims', [0 seconds(diff(tlims))], 'lims', lims, ...
    'showtitle', false);
zlim([min(info.meshdata.z(:)) - 2, 2])
view([30, 45])
title(sprintf('%s lander %d %s: %s to %s, %d tracks of %d animals', country, eventlander, eventcode, ...
    char(tlims(1), 'yyyy-MM-dd HH:mm:ss'), char(tlims(2), 'HH:mm:ss'), numel(loctracks), ...
    numel(unique({loctracks.code}))));
set(gca, 'FontSize', 14);
name = sprintf('test_%s_lander%d_loctracks', eventcode, eventlander);
exportgraphics(fig, fullfile(outfolder, [name '.png']), 'Resolution', 150);
savefig(fig, fullfile(outfolder, [name '.fig']));
fprintf('Saved %s\n', fullfile(outfolder, [name '.png']));
