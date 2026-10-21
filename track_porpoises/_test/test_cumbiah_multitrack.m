%% Test the CUMBIAH bearing tracking on a short section of data
%
% Runs the same tracking as cumbiah_multitrack.m (TRACK_BEARINGS) on the
% porpoise clicks of one lander between TSTART and TEND, and plots the
% tracking stages (PLOT_BEARING_TRACKS). Nothing is saved: no cache, no
% database, no .mat, no figure files. It is for quickly trying out the
% tracking settings on a section of interest.
%
% The section is tracked as a whole - there is no splitting into
% encounters and the boat calibration trials are not left out - so pick a
% section that has porpoises in it. trackargs below start as a copy of
% those in cumbiah_multitrack.m; change them here to try new settings, then
% copy the ones that work back.
%
% Needs the CUMBIAH library, soundnet and PAMGUARD on the MATLAB path.
clear
close all

%% Inputs
country      = 'Denmark';
landernumber = 1;
deployment   = 1;

% section to track, on the lander's clock
tstart = datetime(2024, 10, 5, 18, 29, 0);
tend   = datetime(2024, 10, 5, 18, 59, 0);

% clicks
porptype = 1;           % porpoise classification flag
minamp = -1000;         % minimum click amplitude (dB)
usevertical = false;    % also track on the vertical angle of the clicks

% bearing tracks (see cumbiah_multitrack.m for what these do)
trackargs = {'echoWindow', 0.0025, ... % clicks this soon after a focal click are echoes (s)
    'windowLen', 2, ...     % fragment window (s)
    'kdeSigma', 3, ...      % bearing density smoothing (deg)
    'peakMinSep', 10, ...   % min bearing separation of two animals in a window (deg)
    'fragTol', 8, ...       % max click bearing distance from its fragment (deg)
    'minFragClicks', 4, ... % min clicks per fragment
    'measSigmaMin', 2, ...  % min fragment bearing error (deg)
    'processNoise', 1, ...  % how fast the bearing rate may change (deg^2/s^3)
    'rateSigma0', 5, ...    % bearing rate a new track may have (deg/s)
    'maxGap', 30, ...       % max gap before a track is ended (s)
    'minTrackFrags', 3, ... % min fragments for a track...
    'minTrackClicks', 30, ... % ...or two fragments with this many clicks, for a short dense run
    'smoothFrags', 1, ...   % no median smoothing of the track: the fragments are clean
    'stitchGap', 60, ...    % max gap when re-joining broken tracks (s)
    'stitchTol', 20, ...    % bearing tolerance when re-joining (deg)
    'maxStitchRate', 8, ... % max bearing rate when re-joining (deg/s)
    'mopUp', true, ...      % pick up fragments the tracker missed
    'mopTol', 10, ...       % bearing tolerance when picking them up (deg)
    'clickTrains', true, ... % follow fast bearing sweeps (an animal close by) click by click
    'trainMinClicks', 12, ... % min clicks in such a train
    'clickTol', 8};         % max click bearing distance from track (deg)

%% Porpoise clicks of the section
[startTime, ~, serialnumber] = getlanderdeploymentinfo(landernumber, deployment, country);
data = getlanderpaths(serialnumber, startTime);
tlims = datenum([tstart tend]);
fprintf('%s lander %d, deployment %d: %s to %s\n', country, landernumber, deployment, ...
    datestr(tlims(1)), datestr(tlims(2)));

clicks = load_porpoise_clicks(data.binaryfolder, tlims, porptype, minamp);
[clktimes, order] = sort([clicks.date]');
clicks = clicks(order);
% bearings relative to the lander (deg)
angles = clkstruct2bearings(clicks);
bearings = angles(:,2);
vertical = angles(:,3);
fprintf('%d porpoise clicks\n', numel(clktimes));

%% Tracks
tic
if usevertical
    res = track_bearings(clktimes, bearings, vertical, trackargs{:});
else
    res = track_bearings(clktimes, bearings, trackargs{:});
end
fprintf('Tracked in %.1f s\n', toc);

ntracks = numel(res.tracks);
fprintf('%d tracks, %d of %d clicks on a track (%d echoes)\n', ntracks, ...
    sum(res.clickTrack > 0), numel(clktimes), sum(res.isEcho));
[~, order] = sort(arrayfun(@(T) T.tnum(1), res.tracks));
for i = 1:ntracks
    T = res.tracks(order(i));
    fprintf('  track %2d: %s - %s  %4d clicks\n', order(i), datestr(T.tnum(1), 'HH:MM:SS'), ...
        datestr(T.tnum(end), 'HH:MM:SS'), T.nClicks);
end

%% Plot
figure('Position', [50 50 1500 950]);
if usevertical
    plot_bearing_tracks(clktimes, bearings, res, vertical);
else
    plot_bearing_tracks(clktimes, bearings, res);
end
sgtitle(sprintf('TEST %s lander %d, deployment %d: %s - %s (bearings relative to the lander)', ...
    country, landernumber, deployment, datestr(tlims(1), 'dd/mm/yyyy HH:MM'), ...
    datestr(tlims(2), 'HH:MM')), 'FontSize', 11, 'Interpreter', 'none');

%% ------------------------------------------------------------------------
function clicks = load_porpoise_clicks(binaryroot, tlims, porptype, minamp)
% clicks of type porptype above minamp (dB) between tlims (datenum) from
% the binary files under binaryroot, with the waveforms dropped (as in
% cumbiah_multitrack.m)
files = dir(fullfile(binaryroot, '**', 'Click_Detector_Click_Detector_Clicks_*.pgdf'));
ftime = nan(numel(files), 1);
for i = 1:numel(files)
    tok = regexp(files(i).name, '(\d{8}_\d{6})\.pgdf$', 'tokens', 'once');
    if ~isempty(tok)
        ftime(i) = datenum(tok{1}, 'yyyymmdd_HHMMSS');
    end
end
% files that could hold clicks in the time limits (a file runs until the
% next one starts)
[ftime, order] = sort(ftime);
files = files(order);
fend = [ftime(2:end); inf];
use = find(fend >= tlims(1) & ftime <= tlims(2));

keep = {'date', 'millis', 'UID', 'channelMap', 'fileName', 'angles'};
clicks = cell(numel(use), 1);
for i = 1:numel(use)
    f = files(use(i));
    fprintf('  loading %d of %d: %s\n', i, numel(use), f.name);
    evalc(['c = loadPamguardBinaryFolder(f.folder, f.name, 0, ' ...
        '@(x) passtypeclicks(x, porptype, minamp, tlims));']);
    if ~isempty(c)
        clicks{i} = rmfield(c(:), setdiff(fieldnames(c), keep));
    end
end
clicks = vertcat(clicks{:});
if isempty(clicks)
    error('No porpoise clicks (type %d) between %s and %s in %s.', porptype, ...
        datestr(tlims(1)), datestr(tlims(2)), binaryroot);
end
end
