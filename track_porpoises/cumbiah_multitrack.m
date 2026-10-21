%% Porpoise bearing tracks of a single CUMBIAH lander
%
% Pick a country, a lander and a deployment, and the PAMGuard database the
% tracks are to be saved to. The porpoise clicks of the deployment are cut
% into encounters (FIND_ENCOUNTERS), the clicks of each encounter are
% grouped into bearing tracks, one per animal (TRACK_BEARINGS), and the
% tracks are written as events to the database (WRITE_TRACK_EVENTS), where
% they can be checked and edited in the PAMGuard viewer.
%
% This is the single device half of the CIBBRiNA iceland_multitrack.m: the
% tracking is the same code (soundnetloc_mat/click_train_tracking) but
% there is no second device here, so no clock offset, no heading offset
% between devices and no association.
%
% DATABASE. The tracks go to TRACKDB, the lander's ..._porpoise.sqlite3
% database of the data struct (DATA.PORPOISEDB). It has to exist already -
% the script does not make it. A lander
% has one database for all of its deployments, so the event number in a
% track's code carries the deployment: PP1003AB01 is deployment 1,
% encounter 3, track AB (the second track of the encounter, in time order).
% The 01 is the fragment number of the two device codes and is always 01
% here; it keeps the codes the same length as the CIBBRiNA ones.
% With overwrite = false the script stops before doing any work if the
% database already has tracks of this deployment, so an analyst's edits are
% not lost by running it twice.
%
% ENCOUNTERS (FIND_ENCOUNTERS). Time is cut into minutes. A minute with at
% least minpermin clicks is active, and an encounter is a run of active
% minutes with no gap of more than maxgap minutes. Encounters longer than
% maxduration are split at their longest silence. The boat calibration
% trials, which are full of clicks classified as porpoise, are left out.
% Encounters are numbered in time order within the period run, so TLIMS
% must stay the same between runs of a deployment or the codes will not
% refer to the same encounters.
%
% BEARINGS. The click bearings are left relative to the lander. It sits
% still on the seabed, so its orientation makes no difference to which
% clicks make up a track; it is applied later, when the tracks are located.
%
% Output, in OUTFOLDER:
%   lander<N>_dep<D>_multitrack.mat  - the encounters and the tracks of each
%   lander<N>_dep<D>_PPnnnn_tracks.png - the three tracking stages of each
%                                      encounter (PLOT_BEARING_TRACKS)
%
% Needs the CUMBIAH library, soundnet and PAMGUARD on the MATLAB path.
clear
close all

%% Inputs
% Lander and deployment numbers are per country - for Denmark, landers 1-9
% and deployments 1 = Oct 24, 2 = Feb 25, 3 = June 25.
country      = 'Denmark';
landernumber = 1;
deployment   = 1;

% Deployment
[startTime, endTime, serialnumber] = getlanderdeploymentinfo(landernumber, deployment, country);

%% Required inputs
data = getlanderpaths(serialnumber, startTime);
name = sprintf('lander%d_dep%d', landernumber, deployment);

% The PAMGuard database the tracks are written to: the lander's
% ..._porpoise.sqlite3 database of the data struct (GETLANDERPATHS), which
% is also where LOCALISEPORPOISES reads them from. It must already exist
% and be a database of this lander's binary store (a copy of the annotated
% database is the usual choice).
trackdb = data.porpoisedB;

%where to temporarily store the clicks in .mat files for faster access. 
cachedir = '/Users/jdjm/Library/CloudStorage/Dropbox/SMRU_research/2026-27_CUMBIAH/landers/cache';

writedb = true;         % write the tracks to trackdb
overwrite = true;      % replace this deployment's tracks already in trackdb.
                        % false = stop if there are any, so analyst edits are safe
encounters = [];        % encounters to run, e.g. 3:5; [] = all of them
tlims = [];             % [start end] datetime to run; [] = the whole deployment
savefigs = true;        % save a figure of the tracks of each encounter
outfolder = '';         % results folder; '' = <lander folder>/multitrack

% clicks
porptype = 1;           % porpoise classification flag
minamp = -1000;         % minimum click amplitude (dB)
usevertical = false;    % also track on the vertical angle of the clicks

% encounters
minpermin = 10;         % clicks in a minute for it to be active
maxgap = 5;             % minutes with no active minute which end an encounter
encpad = 1;             % time added either side of an encounter (min)
minclicks = 100;        % min clicks in an encounter
maxduration = 60;       % longer encounters are split at their longest silence (min)
boattypes = {'bc'};     % event types of the boat calibration trials
boatpad = 2;            % time either side of a boat calibration left out (min)

% Bearing tracks. A lander sits still, so the bearings of an animal do not
% undulate as they do on the free floating CIBBRiNA devices: the clicks lie
% on a clean line, and all of the change in bearing is the animal moving,
% which can be fast when it passes close by. So, compared with
% iceland_multitrack.m, the windows are shorter and the tolerances tighter,
% and the bearing is allowed to change faster. A large, steady change in
% bearing is an animal close to the lander, which is the last thing to
% miss, so the clicks the windows could not follow are followed one at a
% time (clickTrains).
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

if isempty(outfolder)
    outfolder = fullfile(getlandersuperfolder(country), sprintf('lander%d', landernumber), 'multitrack');
end
cachefolder = fullfile(cachedir, 'cumbiah_multitrack');
if ~exist(outfolder, 'dir'), mkdir(outfolder); end
if ~exist(cachefolder, 'dir'), mkdir(cachefolder); end

if isempty(tlims)
    tlims = [startTime endTime];
end
tlims = datenum(tlims);
eventbase = 1000*deployment; % PP1001... for deployment 1, PP3001... for deployment 3
fprintf('%s lander %d, deployment %d: %s to %s\n', country, landernumber, deployment, ...
    datestr(tlims(1)), datestr(tlims(2)));

% the database is the user's choice, and it has to be there
if writedb
    if isempty(trackdb)
        error(['Set trackdb to the PAMGuard database the tracks are to be written to, or ' ...
            'writedb = false to write nothing.']);
    end
    if ~isfile(trackdb)
        error('The database %s does not exist.', trackdb);
    end
    % do not overwrite an analyst's edits by accident
    if ~overwrite
        n = count_events(trackdb, sprintf('PP%d', deployment));
        if n > 0
            error(['%d deployment %d tracks are already in %s.\nSet overwrite = true to replace ' ...
                'them, or writedb = false to leave the database alone.'], n, deployment, trackdb);
        end
    end
    % the viewer needs the event type in its lookup table to show the events
    add_event_type(trackdb, 'pp', 'porpoise');
end

%% Porpoise clicks of the period
cachefile = fullfile(cachefolder, sprintf('clicks_%s_%s.mat', lower(country), name));
c = [];
if exist(cachefile, 'file')
    c = load(cachefile);
    if ~isequal(c.tlims, tlims) || c.porptype ~= porptype || c.minamp ~= minamp
        c = [];
    end
end
if isempty(c)
    fprintf('Loading porpoise clicks (slow)\n');
    c.clicks = load_porpoise_clicks(data.binaryfolder, tlims, porptype, minamp);
    c.tlims = tlims;
    c.porptype = porptype;
    c.minamp = minamp;
    save(cachefile, '-struct', 'c');
else
    fprintf('Loading cached porpoise clicks\n');
end
[alltimes, order] = sort([c.clicks.date]');
allclicks = c.clicks(order);
clear c
% bearings relative to the lander (deg)
angles = clkstruct2bearings(allclicks);
allbearings = angles(:,2);
allvertical = angles(:,3);
fprintf('%d porpoise clicks\n', numel(alltimes));

%% Encounters
% the boat calibration trials are not porpoises
boat = zeros(0, 2);
for db = unique({trackdb, data.sqlitedB, data.rawsqlitedB})
    if isfile(db{1})
        boat = [boat; boat_event_times(db{1}, boattypes, tlims)]; %#ok<AGROW>
    end
end
boat = boat + [-1 1]*boatpad/1440;
enc = find_encounters(alltimes, 'minPerMin', minpermin, 'maxGap', maxgap, 'pad', encpad, ...
    'minClicks', minclicks, 'maxDuration', maxduration, 'exclude', boat, 'tlims', tlims);
if numel(enc) > 999
    error(['%d encounters, but the track codes only have room for 999 in a deployment. ' ...
        'Raise minpermin or minclicks.'], numel(enc));
end
fprintf('\n%d encounters:\n', numel(enc));
for k = 1:numel(enc)
    enc(k).number = eventbase + k;
    enc(k).code = sprintf('PP%04d', enc(k).number);
    fprintf('  %s  %s - %s  %5.1f min  %6d clicks\n', enc(k).code, ...
        datestr(enc(k).tlims(1), 'dd/mm HH:MM:SS'), datestr(enc(k).tlims(2), 'HH:MM:SS'), ...
        enc(k).duration, enc(k).nClicks);
end
if isempty(encounters)
    encounters = 1:numel(enc);
end

%% Tracks of each encounter
% overwrite: clear the old tracks first, including those of encounters
% which have no tracks this time. A run of every encounter clears the whole
% deployment, because the encounter numbers may have changed.
if writedb && overwrite
    if isequal(encounters, 1:numel(enc))
        ndeleted = delete_events(trackdb, sprintf('PP%d', deployment));
    else
        ndeleted = 0;
        for k = encounters
            ndeleted = ndeleted + delete_events(trackdb, enc(k).code);
        end
    end
    fprintf('\nDeleted %d old tracks from %s\n', ndeleted, trackdb);
end
nwritten = 0;
for k = encounters
    fprintf('\n--- %s: %s - %s ---\n', enc(k).code, datestr(enc(k).tlims(1)), ...
        datestr(enc(k).tlims(2), 'HH:MM:SS'));
    in = alltimes >= enc(k).tlims(1) & alltimes <= enc(k).tlims(2);
    clicks = allclicks(in);
    clktimes = alltimes(in);
    bearings = allbearings(in);
    vertical = allvertical(in);
    if usevertical
        [~, res] = evalc('track_bearings(clktimes, bearings, vertical, trackargs{:})');
    else
        [~, res] = evalc('track_bearings(clktimes, bearings, trackargs{:})');
    end

    % one code for each track, lettered in time order
    ntracks = numel(res.tracks);
    if ntracks > 26^2
        error('%s has %d tracks, more than the two letters of a track code can hold.', ...
            enc(k).code, ntracks);
    end
    [~, order] = sort(arrayfun(@(T) T.tnum(1), res.tracks));
    trackcode = repmat({''}, ntracks, 1);
    for i = 1:ntracks
        if res.tracks(order(i)).nClicks > 0
            trackcode{order(i)} = sprintf('%s%s01', enc(k).code, track_letters(i));
        end
    end

    enc(k).nTracks = ntracks;
    enc(k).trackCode = trackcode;
    enc(k).tracks = res.tracks;
    enc(k).tracklims = cell2mat(arrayfun(@(T) T.tnum([1 end])', res.tracks(:), ...
        'UniformOutput', false));
    fprintf('%d clicks, %d tracks, %d clicks on a track\n', sum(in), ntracks, ...
        sum(res.clickTrack > 0));

    % figure of the tracking stages
    if savefigs && ntracks > 0
        fig = figure('Position', [50 50 1500 950], 'Visible', 'off');
        if usevertical
            plot_bearing_tracks(clktimes, bearings, res, vertical);
        else
            plot_bearing_tracks(clktimes, bearings, res);
        end
        sgtitle(sprintf('%s lander %d, deployment %d, %s: %s - %s (bearings relative to the lander)', ...
            country, landernumber, deployment, enc(k).code, ...
            datestr(enc(k).tlims(1), 'dd/mm/yyyy HH:MM'), datestr(enc(k).tlims(2), 'HH:MM')), ...
            'FontSize', 11, 'Interpreter', 'none');
        exportgraphics(fig, fullfile(outfolder, sprintf('%s_%s_tracks.png', name, enc(k).code)), ...
            'Resolution', 150);
        close(fig);
    end

    % write the tracks to the PAMGuard database
    if writedb
        n = write_track_events(trackdb, clicks, res.clickTrack, trackcode, ...
            'eventType', 'pp', 'overwrite', overwrite);
        nwritten = nwritten + n;
        fprintf('Wrote %d events\n', n);
    end
end

%% Save
mt.country = country;
mt.landernumber = landernumber;
mt.deployment = deployment;
mt.serialnumber = serialnumber;
mt.created = datestr(now, 'yyyy-mm-dd HH:MM:SS');
mt.conventions = ['tlims and tracklims are datenum on the lander''s clock; track bearings are ' ...
    'degrees relative to the lander'];
mt.database = trackdb;
mt.tlims = tlims;
mt.usevertical = usevertical;
mt.encounters = enc;
mt.run = encounters;    % the encounters run this time
mt.trackargs = trackargs;
matfile = fullfile(outfolder, sprintf('%s_multitrack.mat', name));
save(matfile, 'mt');
fprintf('\nSaved %s\n', matfile);
if writedb
    fprintf('%d events written to %s\n', nwritten, trackdb);
end
if savefigs
    fprintf('Figures saved in %s\n', outfolder);
end

%% ------------------------------------------------------------------------
function clicks = load_porpoise_clicks(binaryroot, tlims, porptype, minamp)
% clicks of type porptype above minamp (dB) between tlims (datenum) from
% the binary files under binaryroot, one file at a time with the waveforms
% dropped to save memory
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

% only what is needed to track the clicks and write them as events
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

function s = track_letters(g)
% 1 -> AA, 2 -> AB, ... 26 -> AZ, 27 -> BA
g = g - 1;
s = [char('A' + floor(g/26)), char('A' + mod(g, 26))];
end

function n = count_events(dbfile, prefix)
% number of events whose comment starts with prefix
conn = sqlite(dbfile, 'readonly');
c = onCleanup(@() close(conn));
r = fetch(conn, sprintf(['select count(*) as n from Click_Detector_OfflineEvents ' ...
    'where comment like ''%s%%'''], prefix));
n = double(r.n);
end

function n = delete_events(dbfile, prefix)
% delete the events whose comment starts with prefix, and their clicks
n = count_events(dbfile, prefix);
if n == 0
    return
end
conn = sqlite(dbfile);
c = onCleanup(@() close(conn));
like = ['''' prefix '%'''];
execute(conn, ['delete from Click_Detector_OfflineClicks where EventId in ' ...
    '(select Id from Click_Detector_OfflineEvents where comment like ' like ')']);
execute(conn, ['delete from Click_Detector_OfflineEvents where comment like ' like]);
end

function add_event_type(dbfile, code, text)
% add an event type to the PAMGuard lookup table if it is not there
conn = sqlite(dbfile);
c = onCleanup(@() close(conn));
r = fetch(conn, ['select count(*) as n from Lookup where Topic = ''OfflineRCEvents'' ' ...
    'and trim(Code) = ''' code '''']);
if double(r.n) > 0
    return
end
r = fetch(conn, 'select ifnull(max(Id), 0) as id, ifnull(max(DisplayOrder), 0) as ord from Lookup');
execute(conn, sprintf(['insert into Lookup (Id, Topic, DisplayOrder, Code, ItemText, isSelectable) ' ...
    'values (%d, ''OfflineRCEvents'', %d, ''%s'', ''%s'', 1)'], double(r.id) + 1, ...
    double(r.ord) + 10, code, text));
fprintf('Added event type %s to %s\n', code, dbfile);
end

function lims = boat_event_times(dbfile, eventtypes, tlims)
% start and end (datenum) of the events of the given types in tlims
conn = sqlite(dbfile, 'readonly');
c = onCleanup(@() close(conn));
r = fetch(conn, 'select UTC, EventEnd, eventType from Click_Detector_OfflineEvents');
lims = zeros(0, 2);
for i = 1:height(r)
    if ~ismember(strtrim(char(r.eventType(i))), eventtypes)
        continue
    end
    t = datenum([datetime(char(r.UTC(i)), 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS'), ...
        datetime(char(r.EventEnd(i)), 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS')]);
    if t(2) > tlims(1) && t(1) < tlims(2)
        lims(end+1,:) = t; %#ok<AGROW>
    end
end
end
