%% Test: localise simulated porpoise tracks around a lander array
%
% Simulates porpoises swimming around an array of three landers, makes the
% clicks each lander would record, runs LOCALISEPORPOISES on them and
% compares the localised tracks with the true ones.
%
%   1. The array: three landers on a ~30 m triangle on the seabed, each
%      with its own heading, pitch and roll and its own clock offset. They
%      are saved as LOCATE_ARRAY saves them (LOCSTABLE in ARRAYFILE).
%   2. The tracks: known 3D tracks of four animals in three encounters, two
%      of the animals at the same time. The true tracks are saved in the
%      format of LOCTRACKS (XH, LOCTRACKTIMES, DATESTART...).
%   3. The clicks: a porpoise clicks in a narrow beam, which it scans from
%      side to side and up and down about the way it swims. A lander hears
%      a click if it is loud enough after spreading, absorption and the
%      loss off the axis of the beam, and then with a chance PDETECT, so
%      each lander hears the animal in bursts. Each click has, as
%      PAMGuard would record it, the time it arrives on the lander's own
%      clock, the time delays between the hydrophones (with errors from
%      its SNR, as ERROR_TDOA) and the bearing and slant angle worked out
%      from those time delays, all in the frame of the hydrophones (not
%      rotated by the orientation of the lander). Real clicks are not
%      that clean, so some are spoilt as they are in the real data: a
%      fixed extra delay on one hydrophone (the unexplained ~4-5 us of
%      channel 3), now and then a time delay from the wrong peak of the
%      cross correlation, and surface echoes, which the tracker takes as
%      clicks of the same track. The clicks of each animal
%      on each lander are one track, coded as CUMBIAH_MULTITRACK codes
%      them (PP1001AA01). They are saved, one .mat file per lander, as
%      LOAD_EVENT_CLICKS returns them (CLICK_EVENTS) with the hydrophones.
%   4. LOCALISEPORPOISES reads the .mat files (DATA.CLICKSFILE) instead of
%      the databases and binary stores, finds the clocks, matches the
%      tracks and localises them.
%   5. Checks: the positions of the landers, the clock offsets, the
%      matching of the tracks (every association is one animal and every
%      animal is one association) and the error of the localised tracks
%      against the true ones. A figure compares the tracks.
%
% The orientation of the landers is put on the hydrophones here with its
% own rotation matrix (heading, pitch and roll, ZYX), not with the code of
% LOCALISEPORPOISES, so the test checks that the two agree.
%
% Needs the CUMBIAH library, soundnet, PAMGUARD, the CIBBRiNA soundtrap_4c
% code and the particle filter on the MATLAB path.
clear
close all

%% Inputs
outfolder = fullfile(tempdir, 'cumbiah_test_simulated'); % everything is written here
seed = 1;               % random number seed (the clicks and the particle filter)

% the array: m east and north of REFLATLON, whose middle it is
reflatlon = [54.7476 12.5334];
landernumbers = [1 2 3];
deployment = 1;
landerxy = 30/sqrt(3)*[cosd([90; 210; 330]), sind([90; 210; 330])] + [1.5 -2; -1 1; 2 0.5];
landerxy = landerxy - mean(landerxy, 1);
depth = 17;                              % depth of the landers (m)
hpr = [35 2 -1; 160 -3 2; -100 1 3];     % heading, pitch, roll of each lander (deg)
clockoffset = [0 0.8 -0.5];              % lander clock - true time (s)

% the hydrophones of a lander as PAMGuard has them (lander 1's database)
hydrophones = [0 0.0375 0; -0.0325 -0.0188 0; 0.0325 -0.0188 0; 0 0 -0.0990];

% the clicks
soundspeed = 1500;      % (m/s)
t0 = datetime(2024, 10, 20, 12, 0, 0);   % time 0 of the tracks
% mean inter click interval (s); each is jittered so the comb filter has
% one peak. The comb filter of the clocks needs a long ICI: the peak over
% the background of the comb is about 1 + ICI/(2*smoothing window), and the
% window is 2*baseline/c + 5 ms = 45 ms here, so an ICI shorter than about
% 0.15 s falls below MINCOMBSNR = 3 and the clocks are not found
ici = 0.2;
icijitter = 0.05;       % st dev of the jitter (s)
snr1m = 90;             % SNR of a click at 1 m on the axis of the beam (dB)
absorption = 0.03;      % (dB/m)
beamwidth = 15;         % half width of the beam where it is 3 dB down (deg)
maxbeamloss = 50;       % loss off the axis of the beam is at most this (dB)
scan = [45 15];       % the beam scans this far either side of the swim direction (deg), [side up]
scanperiod = [2.5 3.7]; % ... with these periods (s)
minsnr = 10;            % quieter clicks are not detected (dB)
pdetect = 0.8;          % chance a click loud enough is detected
% The SNR of the click waveform in the binary file (SNR_CLICKS), which
% sets the time delay error (ERROR_TDOA), is much lower and narrower than
% the detection SNR: on lander 3, deployment 1, its median is 3.5 dB (10-90%
% -0.3 to 12 dB), a time delay error of ~13 us. It is (SNR - MINSNR)*SNRSCALE
snrscale = 1/3;
% what spoils the real clicks
channeldelay = [0 0 0 4.5e-6]; % extra delay of each hydrophone (s), e.g. the ~4-5 us of channel 3
poutlier = 0.1;         % chance a click has one time delay from the wrong cross correlation peak
pecho = 0.3;            % chance a detected click is followed by its surface echo, if that is loud enough
echoloss = 6;           % loss of the surface reflection (dB)

% the animals: waypoints [t x y z] (s, m east, north and up), joined
% smoothly. The encounter number is the first number of the track codes.
% MAXERR is the largest median 3D error (m) of its localised track that
% passes. A swims almost along the line through landers 2 and 1, so their
% bearings hardly cross and lander 3, behind it, hears little: a weak
% geometry, which is allowed a larger error.
animals = struct( ...
    'name', {'A', 'B', 'C', 'D'}, ...
    'encounter', {1, 2, 2, 3}, ...
    'maxerr', {6, 3, 3, 3}, ...
    'waypoints', { ...
        [0 -50 -20 -6; 20 -15 10 -8; 40 10 40 -10], ...             % past the array, along landers 2 and 1
        [600 50 25 -4; 620 15 5 -6; 640 -30 -15 -8], ...            % through the middle of the array
        [600 -55 -50 -12; 620 -30 -25 -11; 640 -5 -10 -12], ...     % at the same time, in from the south west
        [1200 20 20 -2; 1215 5 18 -9; 1230 -20 10 -14]});           % a dive

% localisation
nruns = 3;              % runs of the particle filter
particles = 5000;       % particles in each run; with 1000 the 'gaussian' likelihood is unsteady (A wanders 6 m between runs)
likelihood = 'inverse';  % weight of a particle from its time delay chi2 (CETWEIGHTTD): 'inverse' or 'gaussian'

% pass/fail
maxlandererr = 0.1;     % lander positions (m)
% clock offsets (s). The comb peak is anywhere in its smoothing window
% (45 ms), and the clocks only have to put the clicks in order
maxclockerr = 0.05;

%% Paths
here = fileparts(mfilename('fullpath'));
folders = strsplit(genpath(fileparts(fileparts(here))), pathsep);
[~, names] = cellfun(@fileparts, folders, 'UniformOutput', false);
folders = folders(~ismember(names, {'_old', '_test', '_tests', ''}) & ~contains(folders, [filesep '.']));
addpath(strjoin(folders, pathsep));
if ~isfolder(outfolder), mkdir(outfolder); end
rng(seed);

%% 1. The array
nl = numel(landernumbers);
landerxyz = [landerxy, repmat(-depth, nl, 1)];
latlon = reflatlon + [landerxy(:,2)/(60*1852), landerxy(:,1)./(60*1852*cosd(reflatlon(1)))];
locstable = table(landernumbers(:), latlon, hpr, 'VariableNames', {'landernumber', 'locationfine', 'hprfinal'});
arrayfile = fullfile(outfolder, sprintf('sim_array_locations_dep%d.mat', deployment));
landers = landernumbers;
save(arrayfile, 'locstable', 'landers', 'depth', 'deployment');

% the hydrophones of each lander, east north up
hgeo = cell(1, nl);
for d = 1:nl
    hgeo{d} = (array2enu(hpr(d,:))*hydrophones')' + landerxyz(d,:);
end

%% 2. The tracks
truetracks = [];
beam = cell(1, numel(animals));
for a = 1:numel(animals)
    w = animals(a).waypoints;
    % click times: emitted every ICI, jittered
    te = w(1,1) + cumsum(max(0.02, ici + icijitter*randn(ceil(2*range(w(:,1))/ici), 1)));
    te = te(te <= w(end,1));
    xyz = interp1(w(:,1), w(:,2:4), te, 'pchip');
    vel = [gradient(xyz(:,1), te), gradient(xyz(:,2), te), gradient(xyz(:,3), te)];
    L.code = sprintf('SIM_%s', animals(a).name);
    L.encounter = animals(a).encounter;
    L.xh = [xyz, vel]';                 % [x y z vx vy vz] (m, m/s), east north up
    L.loctracktimes = te - te(1);       % s from datestart
    L.datestart = datenum(t0) + te(1)/86400;
    L.dateend = datenum(t0) + te(end)/86400;
    L.reflatlon = reflatlon;
    % the direction of the beam of each click: the swim direction, scanned
    ph = 2*pi*rand(1, 2);
    az = atan2d(vel(:,2), vel(:,1)) + scan(1)*sin(2*pi*te/scanperiod(1) + ph(1));
    el = atan2d(vel(:,3), hypot(vel(:,1), vel(:,2))) + scan(2)*sin(2*pi*te/scanperiod(2) + ph(2));
    beam{a} = [cosd(el).*cosd(az), cosd(el).*sind(az), sind(el)]; %#ok<SAGROW>
    truetracks = [truetracks, L]; %#ok<AGROW>
end
truthfile = fullfile(outfolder, 'sim_truetracks.mat');
save(truthfile, 'truetracks', 'landerxyz', 'hpr', 'clockoffset', 'reflatlon', 'animals');

%% 3. The clicks each lander records
P.c = soundspeed;
P.t0 = datenum(t0);
P.pairs = get_index_array(size(hydrophones, 1)) + 1;
P.D = hydrophones(P.pairs(:,2),:) - hydrophones(P.pairs(:,1),:); % pair vectors in the array frame
P.channeldelay = channeldelay(:);
P.poutlier = poutlier;
P.snr0 = minsnr;
P.snrscale = snrscale;
data = cell(1, nl);
nspoilt = zeros(1, 2); % outliers, echoes
for d = 1:nl
    click_events = [];
    uid = 1000*landernumbers(d);
    for a = 1:numel(animals)
        L = truetracks(a);
        te = (L.datestart - datenum(t0))*86400 + L.loctracktimes;
        xyz = L.xh(1:3,:)';
        r = vecnorm(xyz - landerxyz(d,:), 2, 2);
        offaxis = acosd(min(1, sum(beam{a}.*(landerxyz(d,:) - xyz)./r, 2)));
        snr = snr1m - 20*log10(r) - absorption*r - min(maxbeamloss, 3*(offaxis/beamwidth).^2);
        heard = find(snr >= minsnr & rand(size(r)) < pdetect);
        clicks = struct('UID', {}, 'date', {}, 'angles', {}, 'timeDelays', {}, 'numTimeDelays', {}, 'snr', {});
        for i = heard'
            [clicks(end+1), bad] = make_click(xyz(i,:), te(i), snr(i), hgeo{d}, clockoffset(d), P); %#ok<SAGROW>
            nspoilt(1) = nspoilt(1) + bad;
            % its echo off the sea surface: from the image of the animal
            % above the surface, a little later and quieter
            image = xyz(i,:).*[1 1 -1];
            re = norm(image - landerxyz(d,:));
            snre = snr(i) - 20*log10(re/r(i)) - absorption*(re - r(i)) - echoloss;
            if snre >= minsnr && rand < pecho
                clicks(end+1) = make_click(image, te(i), snre, hgeo{d}, clockoffset(d), P); %#ok<SAGROW>
                nspoilt(2) = nspoilt(2) + 1;
            end
        end
        [~, order] = sort([clicks.date]);
        clicks = clicks(order);
        for i = 1:numel(clicks)
            clicks(i).UID = uid + i;
        end
        uid = uid + numel(clicks);
        if isempty(clicks)
            continue
        end
        % one track per animal, coded as CUMBIAH_MULTITRACK: PP, deployment,
        % encounter, the animal (AA, AB, ... in the encounter), fragment 01
        inenc = find([animals.encounter] == animals(a).encounter);
        k = find(inenc == a);
        E.clicks = clicks;
        E.event_id = numel(click_events) + 1;
        E.date = min([clicks.date]);
        E.end_date = max([clicks.date]);
        E.comment = sprintf('PP%d%03dA%c01', deployment, animals(a).encounter, char('A' + k - 1));
        E.event_type = 'pp';
        E.eventUID = E.event_id;
        E.datestr = datestr(E.date, 'yyyy-mm-dd HH:MM:SS.FFF');
        click_events = [click_events, E]; %#ok<AGROW>
        fprintf('lander%d: %s %d clicks (%s)\n', landernumbers(d), E.comment, numel(clicks), L.code);
    end
    clicksfile = fullfile(outfolder, sprintf('sim_lander%d_clicks.mat', landernumbers(d)));
    save(clicksfile, 'click_events', 'hydrophones');

    % the deployment record, with the clicks file instead of a database
    rec = cumbiahdatadefaults();
    rec.landernumber = landernumbers(d);
    rec.deployment = deployment;
    rec.serialnumber = 9000 + landernumbers(d);
    rec.startTime = t0 - hours(1);
    rec.endTime = t0 + hours(1);
    rec.clicksfile = clicksfile;
    data{d} = rec;
end

fprintf('Spoilt: %d clicks with a time delay from the wrong peak, %d surface echoes\n', nspoilt);

%% 4. Localise
rng(seed);
[loctracks, info] = localiseporpoises(data, arrayfile, 'outfolder', fullfile(outfolder, 'localisation'), ...
    'bathyfile', fullfile(outfolder, 'none.mat'), 'soundspeed', soundspeed, 'nruns', nruns, ...
    'particles', particles, 'likelihood', likelihood, 'usecache', false);

%% 5. Checks
fprintf('\n===== Checks =====\n');
pass = true;

% the landers
landererr = max(vecnorm(info.settings.landerxyz - landerxyz, 2, 2));
pass = report(pass, landererr <= maxlandererr, 'lander positions within %.3f m (max %.2f m)', landererr, maxlandererr);

% the clocks of every encounter, lander - reference lander
enc = info.encounters;
clockerr = 0;
for k = 1:numel(enc)
    in = enc(k).landers;
    clockerr = max(clockerr, max(abs(enc(k).clockoffset(in) - (clockoffset(in) - clockoffset(1)))));
end
pass = report(pass, clockerr <= maxclockerr, 'clock offsets within %.4f s (max %.3f s)', clockerr, maxclockerr);

% the matching: the animal of a track is its encounter and letters, e.g.
% PP1002AB01 is the second animal of encounter 2
pass = report(pass, numel(enc) == max([animals.encounter]), '%d encounters (%d simulated)', ...
    numel(enc), max([animals.encounter]));
nassoc = 0;
for k = 1:numel(enc)
    for g = 1:numel(enc(k).groups)
        codes = [enc(k).groups(g).codes{:}];
        ids = unique(cellfun(@(s) s(4:8), codes, 'UniformOutput', false));
        nassoc = nassoc + 1;
        pass = report(pass, isscalar(ids) && numel(codes) >= 2, '%s%s matches %s on %d landers', ...
            enc(k).code, enc(k).groups(g).letters, strjoin(ids, ' + '), numel(codes));
    end
end
pass = report(pass, nassoc == numel(animals), '%d associations (%d animals)', nassoc, numel(animals));

% the localised tracks against the true ones, at the times of the
% localised points (on the reference lander's clock, so a few ms late)
fprintf('\n%-10s %-6s %6s %10s %10s %10s %10s\n', 'track', 'animal', 'points', 'median 3D', ...
    '90% 3D', 'horiz', 'depth');
err3d = cell(1, numel(loctracks));
for i = 1:numel(loctracks)
    L = loctracks(i);
    ts = (L.datestart - datenum(t0))*86400 + L.loctracktimes(:) - clockoffset(1);
    best = inf;
    for a = 1:numel(truetracks)
        T = truetracks(a);
        tt = (T.datestart - datenum(t0))*86400 + T.loctracktimes(:);
        xyz = interp1(tt, T.xh(1:3,:)', ts);
        e = xyz - L.xh(1:3,:)';
        if median(vecnorm(e, 2, 2), 'omitnan') < best
            best = median(vecnorm(e, 2, 2), 'omitnan');
            ea = e;
            ia = a;
        end
    end
    name = animals(ia).name;
    err3d{i} = vecnorm(ea, 2, 2);
    fprintf('%-10s %-6s %6d %8.2f m %8.2f m %8.2f m %8.2f m\n', sprintf('%s/%d', L.code, L.fragment), ...
        name, numel(ts), best, prctile(err3d{i}, 90), median(vecnorm(ea(:,1:2), 2, 2), 'omitnan'), ...
        median(abs(ea(:,3)), 'omitnan'));
    pass = report(pass, best <= animals(ia).maxerr, '%s fragment %d (%s): median error %.2f m (max %.1f m)', ...
        L.code, L.fragment, name, best, animals(ia).maxerr);
end
pass = report(pass, ~isempty(loctracks), '%d tracks localised', numel(loctracks));

%% The tracks: true against localised
fig = figure('Position', [50, 50, 1500, 700], 'Color', 'w');
tl = tiledlayout(2, 2, 'TileSpacing', 'compact');
ax = nexttile(tl, 1, [2 1]); hold(ax, 'on');
cols = lines(numel(truetracks));
h = gobjects(0);
for a = 1:numel(truetracks)
    h(end+1) = plot(ax, truetracks(a).xh(1,:), truetracks(a).xh(2,:), '-', 'Color', cols(a,:), ...
        'LineWidth', 2); %#ok<SAGROW>
end
hl = plot(ax, nan, nan, 'k.', 'MarkerSize', 5);
for i = 1:numel(loctracks)
    plot(ax, loctracks(i).xh(1,:), loctracks(i).xh(2,:), 'k.', 'MarkerSize', 5);
end
hp = plot(ax, landerxyz(:,1), landerxyz(:,2), 'k^', 'MarkerFaceColor', 'y', 'MarkerSize', 10);
axis(ax, 'equal'); grid(ax, 'on'); box(ax, 'on');
xlabel(ax, 'East (m)'); ylabel(ax, 'North (m)'); title(ax, 'Plan view');
legend(ax, [h, hl, hp], [strcat({'true '}, {animals.name}), {'localised', 'landers'}], 'Location', 'best');
ax2 = nexttile(tl, 2); hold(ax2, 'on');
ax3 = nexttile(tl, 4); hold(ax3, 'on');
for a = 1:numel(truetracks)
    T = truetracks(a);
    tt = (T.datestart - datenum(t0))*86400 + T.loctracktimes;
    plot(ax2, tt, -T.xh(3,:), '-', 'Color', cols(a,:), 'LineWidth', 2);
    plot(ax3, tt, hypot(T.xh(1,:), T.xh(2,:)), '-', 'Color', cols(a,:), 'LineWidth', 2);
end
for i = 1:numel(loctracks)
    L = loctracks(i);
    ts = (L.datestart - datenum(t0))*86400 + L.loctracktimes;
    plot(ax2, ts, -L.xh(3,:), 'k.', 'MarkerSize', 5);
    plot(ax3, ts, hypot(L.xh(1,:), L.xh(2,:)), 'k.', 'MarkerSize', 5);
end
set(ax2, 'YDir', 'reverse'); ylabel(ax2, 'Depth (m)'); grid(ax2, 'on'); box(ax2, 'on');
ylabel(ax3, 'Range from the middle (m)'); xlabel(ax3, 'Time (s)'); grid(ax3, 'on'); box(ax3, 'on');
title(tl, 'Simulated tracks (colour) and LOCALISEPORPOISES (black)');
exportgraphics(fig, fullfile(outfolder, 'sim_tracks.png'), 'Resolution', 150);

fprintf('\n');
if pass
    fprintf('PASSED. Results in %s\n', outfolder);
else
    error('test_localise_simulated:failed', 'FAILED - see above. Results in %s', outfolder);
end

%% ------------------------------------------------------------------------
function [c, bad] = make_click(src, te, snr, H, clockoffset, P)
% a click from SRC ([x y z], m) made at TE (s) as a lander with hydrophones
% H (east north up) records it: the time it arrives on the lander's clock,
% the time delays (time at the second hydrophone of each pair - time at the
% first) with the error of a click of this SNR, and the bearing and slant
% PAMGuard works out from them. With a chance P.POUTLIER one time delay is
% from the wrong peak of the cross correlation (BAD).
arrive = vecnorm(src - H, 2, 2)/P.c + P.channeldelay;
c.UID = 0;
c.date = P.t0 + (te + mean(arrive) + clockoffset)/86400;
c.angles = [];
c.timeDelays = [];
c.numTimeDelays = size(P.pairs, 1);
c.snr = (snr - P.snr0)*P.snrscale;
[~, err] = evalc('error_TDOA(c)');
tau = (arrive(P.pairs(:,2)) - arrive(P.pairs(:,1)))' + err{1}'.*randn(1, size(P.pairs, 1));
bad = rand < P.poutlier;
if bad
    j = randi(numel(tau));
    tau(j) = (2*rand - 1)*norm(P.D(j,:))/P.c;
end
c.timeDelays = tau;
% the direction PAMGuard gets from them in the frame of the hydrophones:
% the plane wave from direction u has delays -D*u/c. Angles as in the
% binary files (bearing from +x towards +y, slant up), which
% LOCALISEPORPOISES turns into PAMGuard bearings (0 along +y)
u = -P.c*(P.D\tau');
c.angles = [atan2(u(2), u(1)), atan2(u(3), hypot(u(1), u(2)))];
end

function M = array2enu(hpr)
% rotation of PAMGuard's array frame (x starboard, y forward, z up) to east,
% north, up for a lander with heading, pitch and roll HPR (deg): roll,
% then pitch, then heading (ZYX) in north east down, as ROTATE_BEARINGS
ch = cosd(hpr(1)); sh = sind(hpr(1));
cp = cosd(hpr(2)); sp = sind(hpr(2));
cr = cosd(hpr(3)); sr = sind(hpr(3));
Rz = [ch -sh 0; sh ch 0; 0 0 1];
Ry = [cp 0 sp; 0 1 0; -sp 0 cp];
Rx = [1 0 0; 0 cr -sr; 0 sr cr];
swap = [0 1 0; 1 0 0; 0 0 -1];  % array (x y z) to forward starboard down; and north east down to east north up
M = swap*(Rz*Ry*Rx)*swap;
end

function pass = report(pass, ok, varargin)
% print one check and keep track of whether every check passed
msg = sprintf(varargin{:});
if ok
    fprintf('  ok    %s\n', msg);
else
    fprintf('  FAIL  %s\n', msg);
end
pass = pass && ok;
end
