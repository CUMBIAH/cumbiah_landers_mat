function [loctracks, info] = localiseporpoises(landers, arrayfile, varargin)
%LOCALISEPORPOISES Localise porpoise tracks across an array of landers.
%
%   LOCTRACKS = LOCALISEPORPOISES(LANDERS, ARRAYFILE) brings the lander
%   location (LOCATE_ARRAY) and the single lander bearing tracks
%   (CUMBIAH_MULTITRACK) together: the tracks of each lander are matched
%   between the landers, the clocks of the landers are lined up with a comb
%   filter and the matched tracks are localised with the particle filter.
%
%   LANDERS is a cell array of two or more (usually three) deployment
%   records, one per lander of the array, as returned by GETLANDERPATHS.
%   Each supplies the database holding the lander's porpoise tracks
%   (DATA.PORPOISEDB, ..._porpoise.sqlite3) and its binary store, or, if
%   DATA.CLICKSFILE is set, a .mat file of the clicks of the tracks
%   (CLICK_EVENTS, as LOAD_EVENT_CLICKS returns them, and HYDROPHONES, the
%   array as PAMGuard has it), which is read instead, e.g. for simulated
%   clicks (_test/test_localise_simulated.m). The first lander is the
%   reference: every time is on its clock.
%
%   ARRAYFILE is the .mat file saved by LOCATE_ARRAY, with the position
%   (LOCATIONFINE) and orientation (HPRFINAL) of every lander of the array
%   in LOCSTABLE.
%
%       for i = 1:3
%           [t0, ~, sn] = getlanderdeploymentinfo(i, 1, 'Denmark');
%           landers{i} = getlanderpaths(sn, t0);
%       end
%       arrayfile = fullfile(getlandersuperfolder('Denmark'), 'lander_array_locations_dep1.mat');
%       loctracks = localiseporpoises(landers, arrayfile);
%
%   HOW IT WORKS
%
%   TRACKS. The porpoise tracks are read back from the PAMGuard databases
%   (LOAD_EVENT_CLICKS, without the waveforms), so anything an analyst has
%   changed in the PAMGuard viewer is used. Every event of type PORPTYPES
%   (one per animal) that starts inside the lander's deployment is a track,
%   whether CUMBIAH_MULTITRACK wrote it or it was marked by hand. Event
%   comments and numbers are not used. Tracks during the boat calibration
%   trials (events of type BOATTYPES in any of the landers' databases) are
%   the boat, not porpoises, and are left out.
%
%   ENCOUNTERS. An array encounter is a run of tracks, on any of the
%   landers, with no gap of more than ENCOUNTERGAP minutes. Encounters with
%   tracks on only one lander cannot be localised and are dropped. They are
%   numbered in time order and coded PA<deployment><nnn>, e.g. PA1003 (PA,
%   not PP, because they are not the encounters of any one lander).
%
%   CLOCKS. Each lander is put on the reference lander's clock with a comb
%   filter between the click times of each pair of landers
%   (FIND_TIME_OFFSET). With three landers there are three pairs and only
%   two clocks to find, so the offsets are fitted to all the pairs with a
%   clear comb peak. The clocks start together (CLOCKPRIOR, 0) and drift
%   apart by a second or so a week, so it is done in two passes over every
%   encounter of the deployment, whichever encounters are localised:
%     1. In time order, the offset is searched for within MAXOFFSET of the
%        last one found. A wide search now and then picks the wrong peak,
%        so a line (offset against time, Theil-Sen) is fitted to the
%        offsets of each lander.
%     2. The offset is searched for again within MAXRESIDUAL of that line.
%        An encounter with no clear peak is given the offset of the line.
%   A peak is clear if it has MINCOMBPEAK click pairs and is MINCOMBSNR
%   times the background, the median of the comb out to MAXOFFSET.
%   This is the clock line and comb filter residual of the gill net
%   scripts, with the line found from the porpoises themselves. The clock
%   offset LOCATEPLATFORM fits (RTCTIMEOFFSET) is not used: it is between a
%   lander and the boat GPS in 0.5 s steps, and is not the same from lander
%   to lander for landers whose clocks agree.
%
%   MATCHING. Each pair of landers is associated as the two devices of the
%   gill net data are (ASSOCIATE_TRACKS): the heading bearings of two
%   tracks must cross within MAXRANGE and their click times must line up,
%   and what is still ambiguous is settled by the Hungarian algorithm.
%   Tracks joined through any pair are one animal, so an association can
%   have tracks on two landers or on all of them. Associations are lettered
%   in time order: PA1003AB is the second animal of encounter PA1003.
%
%   ORIENTATION. A lander does not move, so there is no orientation sensor
%   to follow: the hydrophone positions in PAMGuard's array manager are
%   rotated once by the heading, pitch and roll of LOCATE_ARRAY, exactly as
%   LOCATEPLATFORM rotated the bearings to find them (ROTATE_BEARINGS), and
%   put at the lander's position and depth.
%
%   LOCALISATION. The clicks of an association are put in time order, with
%   clicks on different landers within CLKSEARCHWINDOW of each other taken
%   to be the same click, and broken into fragments at gaps of more than
%   MAXTIMEGAP. A fragment needs clicks on at least two landers. Its start
%   location is found with TRACKSTARTLOC_BOUNDED and the particle filter
%   (PARTICE_FILTER_PAM) is run from there, NRUNS times, and averaged. The
%   particle filter does not use the arrival time difference BETWEEN the
%   landers, only the time delays within each, so the clocks only have to
%   be good enough to put the clicks in the right order.
%
%   SEABED. The bathymetry LOCATE_ARRAY cut out around the landers bounds
%   the animals and is the surface of the plots. It is lowered, if it has
%   to be, so that it is SEABEDCLEARANCE below every lander. There is no
%   tide correction: the tide in the western Baltic is a few cm.
%
%   OUTPUT, in OUTFOLDER, where <name> is e.g. landers123_dep1:
%       <name>_loctracks.mat  - LOCTRACKS, SETTINGS, ENCOUNTERS (the clock
%                               offsets and associations of each), NOSTART
%                               (the fragments which could not be started)
%       <name>_PAnnnn_loctracks.png/.fig - every track of an encounter over
%                               the seabed, coloured by time, with the landers
%       <name>_PAnnnn_association.png - the tracks of an encounter on each
%                               lander, coloured by association
%       <name>_clock.png      - the clock offset of each lander through the
%                               deployment, both passes and the line
%
%   LOCTRACKS is a struct array, one element per localised track fragment:
%       code          - encounter and association, e.g. PA1003AB
%       encounter     - encounter number within the deployment
%       fragment      - fragment of the association
%       landers       - lander numbers with clicks in the fragment
%       trackcodes    - the database codes of the tracks of the association
%                       on each lander of the array (cell, one per lander)
%       xh            - [x y z vx vy vz] (m, m/s), east north up of REFLATLON
%       err           - st dev of the particles in x, y, z (m)
%       runsd         - st dev between the runs of the particle filter (m)
%       chi2          - chi2 of each point
%       loctracktimes - seconds from DATESTART
%       startlocation, startconstraint, converge - see TRACKSTARTLOC_BOUNDED
%       datestart, dateend - limits of the encounter (datenum, reference
%                       lander's clock)
%       reflatlon     - [lat lon] of the origin
%       clockoffset   - clock of each lander - reference lander (s)
%
%   INFO holds the encounters, the landers, the clock lines, the seabed
%   mesh, the settings and NOSTART, and in INFO.CLICKS, one element per
%   lander, every click of the tracks inside TLIMS: t (datenum, the
%   lander's own clock - subtract the encounter's CLOCKOFFSET/86400 for the
%   reference clock), trackcode, bearing and slant (deg, true north,
%   positive up) and uvec (unit vector, east north up).
%
%   Name-value options (defaults in brackets):
%
%       'encounters'   - encounters to localise, e.g. 1:3 for PA1001 to
%                        PA1003 of deployment 1 [[] = all]
%       'tlims'        - [start end] (datetime or datenum) of the tracks
%                        used [[] = the whole deployment]. Encounters are
%                        numbered within these limits
%       'localise'     - false stops after the clocks and the matching: the
%                        association figures are made but nothing is
%                        localised or saved [true]
%       'outfolder'    - results folder ['localisation' beside ARRAYFILE]
%       'bathyfile'    - bathymetry .mat of LOCATE_ARRAY
%                        [bathymetry/lander_array_bathymetry_dep<N>.mat
%                        beside ARRAYFILE]. A flat seabed is used if it is
%                        not there
%       'depth'        - depth of the landers (m), one value or one per
%                        lander [the depth saved in ARRAYFILE]
%       'headingcorrection' - added to the heading of each lander (deg),
%                        one per lander [0]
%       'savefigs'     - save the figures [true]
%       'usecache'     - keep the tracks read from each database in TEMPDIR
%                        and reuse them while the database is unchanged [true]
%
%     encounters and clocks
%       'encountergap' - gap between tracks which ends an encounter (min) [5]
%       'porptypes'    - event types of the porpoise tracks [{'pp'}]
%       'boattypes'    - event types of the boat calibration trials [{'bc'}]
%       'boatpad'      - time either side of a boat calibration left out (min) [2]
%       'clockprior'   - clock of each lander - the first lander at the
%                        start of the deployment (s), one per lander [0]
%       'maxoffset'    - first pass: clock offset searched either side of
%                        the last one found (s) [5]
%       'maxresidual'  - second pass: clock offset searched either side of
%                        the clock line (s) [0.25]
%       'mincombsnr'   - comb filter peak/background for a clear peak [3]
%       'mincombpeak'  - click pairs in the peak for a clear peak [15]
%
%     matching
%       'minslant'     - clicks with a true slant angle below this (deg,
%                        negative down) are left out: the landers are on
%                        the seabed, so they cannot hear a porpoise below
%                        them [-10]
%       'trackwindow'  - window the bearings of a track are averaged in (s) [2]
%       'assocargs'    - name-value arguments of ASSOCIATE_TRACKS
%                        [maxRange 500, crossTol 10, crossFrac 0.5,
%                        delayTol 0.002, minMatches 5, timingP 0.01]
%
%     particle filter
%       'soundspeed'   - (m/s) [1500]. Not used where 'propagation' gives one
%       'propagation'  - how sound travels from a porpoise to the landers.
%                        A propagation struct, or a struct array or cell
%                        array of them, in which case the one closest in
%                        time to each encounter is used (SELECT_PROPAGATION):
%                          - a ray traced lookup table of a CTD cast
%                            (MAKE_PROPAGATION_TABLE): the time delays are
%                            predicted from the direction each click really
%                            arrives from, so refraction is allowed for
%                          - a time and a single sound speed
%                            (STRAIGHT_PROPAGATION): straight lines
%                        Its SOUNDSPEED (at the landers) replaces
%                        'soundspeed' for the matching and the particle
%                        filter. [] for straight lines at 'soundspeed' [[]]
%       'propagationmatch' - how the propagation of an encounter is chosen
%                        from several: 'time', the closest in time, or
%                        'season', the closest in time of year, whatever
%                        the year (SELECT_PROPAGATION) ['time']
%       'likelihood'   - how the time delay chi2 of a particle becomes its
%                        weight (CETWEIGHTTD): 'inverse', 1/mean(sqrt(chi2)),
%                        or 'gaussian', exp(-chi2/2). The gaussian is better
%                        on clean simulated clicks (test_localise_simulated)
%                        but on real clicks it is overconfident and jumpy;
%                        the heavy tailed inverse copes with bad delays
%                        ['inverse']
%       'stdaccel'     - st dev of acceleration of the movement model [0.5]
%       'maxspeed'     - (m/s) [4]
%       'nruns'        - runs of the particle filter [5]
%       'particles'    - particles in each run [5000]
%       'clksearchwindow' - clicks this close on two landers are the same
%                        click (s) [0.1]
%       'maxtimegap'   - a track is broken at gaps longer than this (s) [5]
%       'minfragclicks' - min clicks in a fragment [10]
%       'minlanderclicks' - min clicks a lander must have in a fragment to
%                        be used in it [3]
%       'maxstartrange', 'minstartrange', 'startconstraints',
%       'minstartclicks' - the start location: within MAXSTARTRANGE [500 m]
%                        and not closer than MINSTARTRANGE [3 m] to a
%                        lander, of the kinds STARTCONSTRAINTS
%                        [{'crossing','surface','seabed'}], with at least
%                        MINSTARTCLICKS [5] clicks after it
%
%     seabed and plots
%       'seabedclearance' - the seabed is at least this far below every
%                        lander (m) [1]
%       'plotlims'     - half width of the area plotted (m); grows to fit
%                        the tracks [100]
%       'maxplotlims'  - ... up to this [500]
%
%   Needs the CUMBIAH library, soundnet, PAMGUARD, the CIBBRiNA
%   soundtrap_4c/localisation code (ASSOCIATE_TRACKS, FIND_TIME_OFFSET,
%   TRACKSTARTLOC_BOUNDED, READ_PAMGUARD_HYDROPHONES) and the particle
%   filter (MATLAB/localisation) on the MATLAB path - see LOCALISE_PORPOISES.
%
%   See also LOCALISE_PORPOISES, LOCATE_ARRAY, CUMBIAH_MULTITRACK,
%   PLOT_LOCTRACK_LANDERS, ASSOCIATE_TRACKS, PARTICE_FILTER_PAM.

% ---- options -----------------------------------------------------------
p = inputParser;
p.addParameter('encounters', []);
p.addParameter('tlims', []);
p.addParameter('localise', true);
p.addParameter('outfolder', '');
p.addParameter('bathyfile', '');
p.addParameter('depth', []);
p.addParameter('headingcorrection', []);
p.addParameter('savefigs', true);
p.addParameter('usecache', true);
p.addParameter('encountergap', 5);
p.addParameter('porptypes', {'pp'});
p.addParameter('boattypes', {'bc'});
p.addParameter('boatpad', 2);
p.addParameter('clockprior', []);
p.addParameter('maxoffset', 5);
p.addParameter('maxresidual', 0.25);
p.addParameter('mincombsnr', 3);
p.addParameter('mincombpeak', 15);
p.addParameter('minslant', -10);
p.addParameter('trackwindow', 2);
p.addParameter('assocargs', {'maxRange', 500, 'crossTol', 10, 'crossFrac', 0.5, ...
    'delayTol', 0.002, 'minMatches', 5, 'timingP', 0.01});
p.addParameter('soundspeed', 1500);
p.addParameter('propagation', []);
p.addParameter('propagationmatch', 'time');
p.addParameter('likelihood', 'inverse');
p.addParameter('stdaccel', 0.5);
p.addParameter('maxspeed', 4);
p.addParameter('nruns', 5);
p.addParameter('particles', 5000);
p.addParameter('clksearchwindow', 0.1);
p.addParameter('maxtimegap', 5);
p.addParameter('minfragclicks', 10);
p.addParameter('minlanderclicks', 3);
p.addParameter('maxstartrange', 500);
p.addParameter('minstartrange', 3);
p.addParameter('startconstraints', {'crossing', 'surface', 'seabed'});
p.addParameter('minstartclicks', 5);
p.addParameter('seabedclearance', 1);
p.addParameter('plotlims', 100);
p.addParameter('maxplotlims', 500);
p.parse(varargin{:});
opt = p.Results;

% ---- the landers and the array -----------------------------------------
if isstruct(landers)
    landers = num2cell(landers);
end
nl = numel(landers);
if nl < 2
    error('localiseporpoises:landers', ...
        'LANDERS must hold the deployment records of two or more landers.');
end
if ~isfile(arrayfile)
    error('localiseporpoises:noArrayFile', ...
        'The array file %s does not exist - run LOCATE_ARRAY first.', arrayfile);
end
A = load(arrayfile);
if ~isfield(A, 'locstable')
    error('localiseporpoises:badArrayFile', ...
        '%s has no LOCSTABLE - it is not a file saved by LOCATE_ARRAY.', arrayfile);
end
depth = opt.depth;
if isempty(depth)
    if ~isfield(A, 'depth')
        error('localiseporpoises:noDepth', ...
            'No depth in %s - pass the depth of the landers with ''depth''.', arrayfile);
    end
    depth = A.depth;
end
if isscalar(depth)
    depth = repmat(depth, 1, nl);
end
headingcorrection = opt.headingcorrection;
if isempty(headingcorrection)
    headingcorrection = zeros(1, nl);
end
prior = opt.clockprior;
if isempty(prior)
    prior = zeros(1, nl);
end
if numel(depth) ~= nl || numel(headingcorrection) ~= nl || numel(prior) ~= nl
    error('localiseporpoises:perLander', ...
        ['''depth'', ''headingcorrection'' and ''clockprior'' must have one value for each of ' ...
         'the %d landers.'], nl);
end
prior = prior(:)' - prior(1); % lander d - reference lander clock (s)

deployment = landers{1}.deployment;
clear dev
for d = 1:nl
    data = landers{d};
    if isempty(data.landernumber)
        error('localiseporpoises:noDeployment', ...
            ['LANDERS{%d} holds no deployment - GETLANDERPATHS found no lander for that ' ...
             'serial number and time.'], d);
    end
    if data.deployment ~= deployment
        error('localiseporpoises:deployment', ...
            'The landers are not all of one deployment (lander %d is of deployment %d, not %d).', ...
            data.landernumber, data.deployment, deployment);
    end
    row = find(A.locstable.landernumber == data.landernumber);
    if numel(row) ~= 1
        error('localiseporpoises:notInArray', 'Lander %d is not in %s.', data.landernumber, arrayfile);
    end
    if uses_clicksfile(data)
        if ~isfile(data.clicksfile)
            error('localiseporpoises:noClicksFile', 'Lander %d: the clicks file %s does not exist.', ...
                data.landernumber, data.clicksfile);
        end
    elseif ~isfield(data, 'porpoisedB') || isempty(data.porpoisedB) || ~isfile(data.porpoisedB)
        error('localiseporpoises:noDatabase', ...
            ['Lander %d has no porpoise track database (DATA.PORPOISEDB) - run ' ...
             'CUMBIAH_MULTITRACK first.'], data.landernumber);
    end
    dev(d).data = data; %#ok<AGROW>
    dev(d).number = data.landernumber;
    dev(d).name = sprintf('lander%d', data.landernumber);
    dev(d).latlon = A.locstable.locationfine(row,:);
    dev(d).hpr = A.locstable.hprfinal(row,:) + [headingcorrection(d) 0 0];
end
if isfield(A, 'deployment') && A.deployment ~= deployment
    error('localiseporpoises:arrayDeployment', ...
        '%s is of deployment %d but the landers are of deployment %d.', arrayfile, A.deployment, deployment);
end
if numel(unique([dev.number])) ~= nl
    error('localiseporpoises:repeated', 'The same lander is in LANDERS more than once.');
end

name = sprintf('landers%s_dep%d', sprintf('%d', [dev.number]), deployment);
outfolder = opt.outfolder;
if isempty(outfolder)
    outfolder = fullfile(fileparts(arrayfile), 'localisation');
end
bathyfile = opt.bathyfile;
if isempty(bathyfile)
    bathyfile = fullfile(fileparts(arrayfile), 'bathymetry', ...
        sprintf('lander_array_bathymetry_dep%d.mat', deployment));
end
cachefolder = fullfile(tempdir, 'cumbiah_localise');
if ~exist(outfolder, 'dir'), mkdir(outfolder); end
if ~exist(cachefolder, 'dir'), mkdir(cachefolder); end

tlims = opt.tlims;
if isempty(tlims)
    tlims = [max(cellfun(@(D) datenum(D.startTime), landers)), ...
        min(cellfun(@(D) datenum(D.endTime), landers))];
end
tlims = datenum(tlims);

% everything is in metres east and north of the middle of the landers, and
% up from the sea surface
reflatlon = mean(vertcat(dev.latlon), 1);
fprintf('%s, deployment %d: %s to %s\n', strjoin({dev.name}, ', '), deployment, ...
    datestr(tlims(1)), datestr(tlims(2)));
for d = 1:nl
    [~, x, y] = latLong2meters(reflatlon(1), reflatlon(2), dev(d).latlon(1), dev(d).latlon(2));
    dev(d).xyz = [x, y, -depth(d)];
    dev(d).rotm = platform_rotm(dev(d).hpr);
    fprintf('  %s: %.1f m east, %.1f m north, %.1f m deep; heading, pitch, roll %s\n', ...
        dev(d).name, x, y, depth(d), num2str(dev(d).hpr, '%.1f '));
end
landerxyz = vertcat(dev.xyz);

% ---- tracks from the PAMGuard databases --------------------------------
% the boat calibration trials are not porpoises. The boat ran over every
% lander of the array, so a trial marked in one database counts for all.
boat = zeros(0, 2);
for d = 1:nl
    for db = unique({dev(d).data.porpoisedB, dev(d).data.sqlitedB, dev(d).data.rawsqlitedB})
        if isfile(db{1})
            boat = [boat; boat_event_times(db{1}, opt.boattypes, tlims)]; %#ok<AGROW>
        end
    end
end
boat = boat + [-1 1]*opt.boatpad/1440;
for d = 1:nl
    T = load_tracks(dev(d).data, deployment, opt.porptypes, cachefolder, opt.usecache);
    % the hydrophones as PAMGuard has them, rotated to east north up with
    % the orientation of the lander and put where it lies
    dev(d).hydrophones = (dev(d).rotm*T.hydrophones')' + dev(d).xyz;
    % the tracks inside the time limits and clear of the boat
    isboat = any(T.tracklims(:,1) <= boat(:,2)' & T.tracklims(:,2) >= boat(:,1)', 2);
    keep = find(T.tracklims(:,2) >= tlims(1) & T.tracklims(:,1) <= tlims(2) & ~isboat);
    renumber = zeros(numel(T.code), 1);
    renumber(keep) = 1:numel(keep);
    in = renumber(T.track) > 0;
    % the bearings of the clicks, referenced to true north with the
    % orientation of the lander (deg). A lander is on the seabed, so a
    % click from more than -MINSLANT below the horizontal is not a porpoise
    % (a reflection, or a bad time delay) and is left out.
    [b, ned] = rotate_bearings(pamguard_bearings(T.angles(in,:)), dev(d).hpr);
    low = rad2deg(b(:,2)) < opt.minslant;
    index = find(in);
    in(index(low)) = false;
    b = b(~low,:);
    ned = ned(~low,:);
    dev(d).t = T.t(in);
    dev(d).track = renumber(T.track(in));
    dev(d).delays = T.delays(in,:);
    dev(d).tderr = T.tderr(in);
    dev(d).code = T.code(keep);
    dev(d).tracklims = T.tracklims(keep,:);
    dev(d).bearing = rad2deg(b(:,1));
    dev(d).slant = rad2deg(b(:,2));
    dev(d).uvec = [ned(:,2), ned(:,1), -ned(:,3)]; % unit vector of each click, east north up
    fprintf(['%s: %d tracks, %d clicks (%d tracks left out as the boat, %d clicks below %g deg ' ...
        'slant)\n'], dev(d).name, numel(keep), sum(in), sum(isboat), sum(low), opt.minslant);
end

% ---- encounters --------------------------------------------------------
enc = find_array_encounters(dev, prior, opt.encountergap);
for k = 1:numel(enc)
    enc(k).number = 1000*deployment + k;
    enc(k).code = sprintf('PA%04d', enc(k).number);
end
fprintf('\n%d encounters with tracks on two or more landers\n', numel(enc));
encounters = opt.encounters;
if isempty(encounters)
    encounters = 1:numel(enc);
end
encounters = encounters(:)';
if any(encounters < 1 | encounters > numel(enc))
    error('localiseporpoises:encounters', 'There are only %d encounters.', numel(enc));
end

% ---- clocks ------------------------------------------------------------
% found for every encounter, so the encounters which are localised have the
% offsets they would have in a run of them all
baseline = zeros(nl);
for i = 1:nl
    for j = 1:nl
        baseline(i,j) = norm(landerxyz(i,1:2) - landerxyz(j,1:2));
    end
end
tmid = arrayfun(@(E) mean(E.tlims), enc)';
% 1. within maxoffset of the last offset found
pass1 = comb_clocks(enc, dev, baseline, repmat(prior, numel(enc), 1), true, opt.maxoffset, opt.maxoffset, opt);
% the clock line of each lander through those
clockline = struct('t0', tlims(1), 'offset0', num2cell(prior), 'rate', 0, 'n', 0);
expected = zeros(numel(enc), nl);
for d = 2:nl
    use = pass1.found(:,d);
    clockline(d).n = sum(use);
    if any(use)
        [clockline(d).offset0, clockline(d).rate] = robust_line(tmid(use) - tlims(1), pass1.offset(use,d));
    end
    expected(:,d) = clockline(d).offset0 + clockline(d).rate*(tmid - tlims(1));
    fprintf('Clock of %s - %s: %+.3f s at the start, %+.3f s a day (%d encounters)\n', dev(d).name, ...
        dev(1).name, clockline(d).offset0, clockline(d).rate, clockline(d).n);
end
% 2. within maxresidual of the line
pass2 = comb_clocks(enc, dev, baseline, expected, false, opt.maxresidual, opt.maxoffset, opt);
for k = 1:numel(enc)
    enc(k).clockoffset = pass2.offset(k,:);  % lander - reference lander (s)
    enc(k).clockfound = pass2.found(k,:);    % by the comb filter; false = the clock line
    enc(k).clockline = expected(k,:);
    enc(k).combsnr = pass2.snr(:,:,k);       % comb peak/background of each pair
    enc(k).combpeak = pass2.peak(:,:,k);     % click pairs in the comb peak of each pair
end
if opt.savefigs && ~isempty(enc)
    fig = figure('Position', [50 50 1100 500], 'Visible', 'off');
    plot_clocks(tmid, pass1, pass2, expected, dev);
    exportgraphics(fig, fullfile(outfolder, [name '_clock.png']), 'Resolution', 150);
    close(fig);
end

% ---- the seabed --------------------------------------------------------
meshlim = max(opt.maxplotlims, opt.maxstartrange) + max(abs(landerxyz(:,1:2)), [], 'all');
[meshdata, bathysource] = seabed_mesh(bathyfile, reflatlon, meshlim, -max(depth));
% lowered, if it has to be, to keep it below the landers
zbed = interp2(meshdata.x, meshdata.y, meshdata.z, landerxyz(:,1), landerxyz(:,2));
depthoffset = min(0, min(landerxyz(:,3) - opt.seabedclearance - zbed));
meshdata.z = meshdata.z + depthoffset;
fprintf('Seabed (%s) at the landers %s m; lowered by %.1f m to clear them\n', bathysource, ...
    num2str((zbed + depthoffset)', '%.1f '), -depthoffset);

% ---- match and localise each encounter ---------------------------------
loctracks = [];
nostart = struct('code', {}, 'fragment', {}, 'nclicks', {}, 'reason', {}, 'converge', {});
for k = encounters
    present = enc(k).landers;
    tenc = enc(k).tlims;
    fprintf('\n--- %s: %s - %s, %s ---\n', enc(k).code, datestr(tenc(1)), ...
        datestr(tenc(2), 'HH:MM:SS'), strjoin({dev(present).name}, ', '));
    fprintf('Clock offsets from %s:', dev(1).name);
    for d = present(present > 1)
        src = 'clock line';
        if enc(k).clockfound(d), src = 'comb filter'; end
        fprintf(' %s %+.3f s (%s)', dev(d).name, enc(k).clockoffset(d), src);
    end
    fprintf('\n');

    % how sound travels in this encounter: the propagation closest in time
    [~, propname, csound, delayfun] = encounter_propagation(opt.propagation, tenc(1), opt.soundspeed, ...
        opt.propagationmatch);
    fprintf('Propagation: %s\n', propname);

    % the clicks of the encounter on each lander, on the reference clock,
    % as the output of TRACK_BEARINGS so they can go to ASSOCIATE_TRACKS
    clear ed
    for d = 1:nl
        ed(d).name = dev(d).name; %#ok<AGROW>
        ed(d).location = dev(d).latlon;
        ed(d).index = zeros(0, 1);
        ed(d).clktimes = zeros(0, 1);
        if ~ismember(d, present)
            continue
        end
        [in, local] = ismember(dev(d).track, enc(k).tracks{d});
        ed(d).index = find(in);
        ed(d).clktimes = dev(d).t(in) - enc(k).clockoffset(d)/86400;
        ed(d).bearings = dev(d).bearing(in);
        ed(d).clicktrack = local(in);
        ed(d).res = tracks2res(ed(d).clktimes, ed(d).bearings, ed(d).clicktrack, ...
            numel(enc(k).tracks{d}), opt.trackwindow);
    end

    %% Match the tracks between each pair of landers
    % tracks joined through any pair are the same animal
    first = cumsum([0, cellfun(@numel, enc(k).tracks)]); % node of track i of lander d: first(d) + i
    edges = zeros(0, 2);
    for i = present
        for j = present(present > i)
            assoc = associate_tracks(ed([i j]), opt.assocargs{:}, 'soundSpeed', csound, ...
                'offset', 0, 'maxOffset', 0.05);
            for g = 1:numel(assoc.groups)
                nodes = [first(i) + assoc.groups(g).tracks{1}(:); first(j) + assoc.groups(g).tracks{2}(:)];
                edges = [edges; repmat(nodes(1), numel(nodes) - 1, 1), nodes(2:end)]; %#ok<AGROW>
            end
        end
    end
    groups = join_tracks(edges, first, ed);
    enc(k).groups = groups;
    for g = 1:numel(groups)
        groups(g).codes = cell(1, nl);
        for d = 1:nl
            groups(g).codes{d} = dev(d).code(enc(k).tracks{d}(groups(g).tracks{d}))';
        end
        fprintf('  %s%s:', enc(k).code, groups(g).letters);
        for d = find(~cellfun(@isempty, groups(g).tracks))
            fprintf(' %s %s;', dev(d).name, strjoin(groups(g).codes{d}, ', '));
        end
        fprintf('\n');
    end
    enc(k).groups = groups;
    if isempty(groups)
        fprintf('No tracks matched between the landers\n');
        continue
    end

    if opt.savefigs
        fig = figure('Position', [50 50 1400 250*numel(present) + 100], 'Visible', 'off');
        plot_association(ed, groups, present);
        sgtitle(sprintf('%s %s: %s - %s, true bearings, %s''s clock', name, enc(k).code, ...
            datestr(tenc(1), 'dd/mm/yyyy HH:MM'), datestr(tenc(2), 'HH:MM'), dev(1).name), ...
            'FontSize', 11, 'Interpreter', 'none');
        exportgraphics(fig, fullfile(outfolder, sprintf('%s_%s_association.png', name, enc(k).code)), ...
            'Resolution', 150);
        close(fig);
    end
    if ~opt.localise
        continue
    end

    %% Localise each association
    enctracks = [];
    for g = 1:numel(groups)
        code = [enc(k).code groups(g).letters];
        cols = find(~cellfun(@isempty, groups(g).tracks)); % the landers of the association

        %% Create data structures
        % every click of the association on each of its landers
        clear G
        for q = 1:numel(cols)
            d = cols(q);
            in = ismember(ed(d).clicktrack, groups(g).tracks{d});
            [t, iu] = unique(ed(d).clktimes(in));
            index = ed(d).index(in);
            index = index(iu);
            G(q).t = t; %#ok<AGROW>
            G(q).delays = num2cell(dev(d).delays(index,:)', 1)';
            G(q).err = arrayfun(@(e) repmat(e, size(dev(d).delays, 2), 1), dev(d).tderr(index), ...
                'UniformOutput', false);
            G(q).hydrophones = repmat({dev(d).hydrophones}, numel(t), 1);
        end

        %% Match Clicks
        % one row per click: clicks matched between landers share a row
        rows = match_rows({G.t}, opt.clksearchwindow);

        %% Create input for a particle filter to track the animal
        n = size(rows, 1);
        tdate = zeros(n, 1);
        timedelaysobs = cell(n, numel(cols));
        timedelayserr = cell(n, numel(cols));
        hydrophonesgeo = cell(n, numel(cols));
        for q = numel(cols):-1:1 % the time of a matched row is that of its first lander
            r = find(rows(:,q) > 0);
            tdate(r) = G(q).t(rows(r,q));
            timedelaysobs(r,q) = G(q).delays(rows(r,q));
            timedelayserr(r,q) = G(q).err(rows(r,q));
            hydrophonesgeo(r,q) = G(q).hydrophones(rows(r,q));
        end
        %must sort everything by time or particle filter will go crazy.
        [tdate, order] = sort(tdate);
        timedelaysobs = timedelaysobs(order,:);
        timedelayserr = timedelayserr(order,:);
        hydrophonesgeo = hydrophonesgeo(order,:);
        timessrt = (tdate - tenc(1))*86400; % seconds from the start of the encounter

        %% Break apart the tracks if the time between clicks is too large
        trackfragments = fragment_tracks(timessrt, timedelaysobs, timedelayserr, hydrophonesgeo, ...
            opt.maxtimegap, opt.minfragclicks, opt.minlanderclicks);
        fprintf('%s: %s clicks, %d matched, %d fragments\n', code, ...
            strjoin(arrayfun(@(S) num2str(numel(S.t)), G, 'UniformOutput', false), ' + '), ...
            sum(sum(rows > 0, 2) > 1), numel(trackfragments));

        %% Run the particle filter.
        for i = 1:numel(trackfragments)
            F = trackfragments(i);
            tstart = tic;
            %Find the start location for the particle filter: the first
            %window of clicks whose directions from the landers meet
            %inside the water within maxstartrange
            [startlocation, index, startinfo] = trackstartloc_bounded(F.timessrt, F.timedelaysobs, ...
                F.timedelayserr, F.hydrophonesgeo, 'bathymetry', meshdata, 'maxRange', opt.maxstartrange, ...
                'minRange', opt.minstartrange, 'clampDepth', true, 'constraints', opt.startconstraints, ...
                'soundSpeed', csound, 'delayFunction', delayfun);
            toofew = ~isempty(startlocation) && numel(F.timessrt) - index + 1 < opt.minstartclicks;
            if isempty(startlocation) || toofew
                why = startinfo.reason;
                if toofew
                    why = 'bearings cross only at the end of the fragment';
                end
                fprintf('  fragment %d: no start location (%s; directions converge by %+.1f deg)\n', ...
                    i, why, startinfo.converge);
                nostart(end+1).code = code; %#ok<AGROW>
                nostart(end).fragment = i;
                nostart(end).nclicks = numel(F.timessrt);
                nostart(end).reason = why;
                nostart(end).converge = startinfo.converge;
                continue
            end
            use = index:numel(F.timessrt);

            %make sure start location is not above the sea surface or below
            %the seabed.
            dpthstartloc = interp2(meshdata.x, meshdata.y, meshdata.z, startlocation(1), startlocation(2));
            if startlocation(3) > 0
                startlocation(3) = 0;
            elseif ~isnan(dpthstartloc) && startlocation(3) < dpthstartloc
                startlocation(3) = dpthstartloc;
            end

            % run the particle filter several times and average
            xh = zeros(6, numel(use), opt.nruns);
            err = zeros(3, numel(use), opt.nruns);
            chi2 = zeros(opt.nruns, numel(use));
            for ii = 1:opt.nruns
                [~, xh(:,:,ii), pf, chi2(ii,:)] = evalc(['partice_filter_pam(F.timessrt(use), ' ...
                    'F.timedelaysobs(use,:), F.hydrophonesgeo(use,:), startlocation, ' ...
                    '''TimeDelayErrors'', F.timedelayserr(use,:), ''Bathymetry'', meshdata, ' ...
                    '''StdAccel'', opt.stdaccel, ''MaxSpeed'', opt.maxspeed, ''SoundSpeed'', ' ...
                    'csound, ''Particles'', opt.particles, ''DelayFunction'', delayfun, ' ...
                    '''Likelihood'', opt.likelihood)']);
                % spread of the particles in x, y and z
                err(:,:,ii) = squeeze(std(pf.particles(1:3,:,:), 0, 2));
                clear pf
            end

            L.code = code;
            L.encounter = k;
            L.fragment = i;
            L.landers = [dev(cols(F.columns)).number];
            L.trackcodes = groups(g).codes;     % database codes of the tracks, per lander of the array
            L.xh = mean(xh, 3);                 % [x y z vx vy vz] (m, m/s), east north up
            L.err = mean(err, 3);               % st dev of the particles in x, y, z (m)
            L.runsd = std(xh(1:3,:,:), 0, 3);   % st dev between runs (m)
            L.chi2 = mean(chi2, 1);
            L.loctracktimes = F.timessrt(use);  % seconds from datestart
            L.startlocation = startlocation;
            L.startconstraint = startinfo.constraint; % 'crossing', 'surface' or 'seabed'
            L.converge = startinfo.converge;    % convergence of the first two landers' directions (deg)
            L.datestart = tenc(1);              % start of the encounter (datenum, reference lander's clock)
            L.dateend = tenc(2);
            L.reflatlon = reflatlon;
            L.clockoffset = enc(k).clockoffset; % lander - reference lander (s)
            L.propagation = propname;          % how the time delays were predicted
            L.soundspeed = csound;              % sound speed at the landers (m/s)
            enctracks = [enctracks, L]; %#ok<AGROW>
            fprintf(['  fragment %d: landers %s, %d clicks, %.0f s, start by %s, median range %.0f m, ' ...
                'depth %.0f m, particle spread %.0f m (%.0f s to run)\n'], i, num2str(L.landers), ...
                numel(use), range(L.loctracktimes), L.startconstraint, ...
                median(hypot(L.xh(1,:), L.xh(2,:))), -median(L.xh(3,:)), median(vecnorm(L.err)), toc(tstart));
        end
    end
    if isempty(enctracks)
        fprintf('%s: nothing localised\n', enc(k).code);
        continue
    end
    loctracks = [loctracks, enctracks]; %#ok<AGROW>

    %% Plot a map of locations: every track of the encounter
    if opt.savefigs
        fig = figure('Position', [0, 0, 1100, 700], 'Visible', 'off');
        % wide enough for the tracks
        xy = [enctracks.xh];
        lims = min(opt.maxplotlims, max(opt.plotlims, 50*ceil(prctile(max(abs(xy(1:2,:))), 95)/50)));
        plot_loctrack_landers(enctracks, landerxyz, meshdata, 'landernumbers', [dev.number], ...
            'timelims', [0 diff(tenc)*86400], 'lims', lims, 'showtitle', false);
        zlim([min(meshdata.z(:)) - 2, 2])
        view([30, 45])
        title(sprintf('%s %s: %s to %s, %d tracks', name, enc(k).code, ...
            datestr(tenc(1), 'yyyy-mm-dd HH:MM:SS'), datestr(tenc(2), 'HH:MM:SS'), numel(enctracks)), ...
            'Interpreter', 'none');
        set(gca, 'FontSize', 14);
        exportgraphics(fig, fullfile(outfolder, sprintf('%s_%s_loctracks.png', name, enc(k).code)), ...
            'Resolution', 150);
        savefig(fig, fullfile(outfolder, sprintf('%s_%s_loctracks.fig', name, enc(k).code)));
        close(fig);
    end
end

% ---- save --------------------------------------------------------------
settings = rmfield(opt, {'encounters', 'outfolder', 'bathyfile', 'savefigs', 'usecache', 'localise', ...
    'clockprior', 'propagation'});
settings.propagation = propagation_summary(opt.propagation); % the tables themselves are not kept
settings.created = datestr(now, 'yyyy-mm-dd HH:MM:SS');
settings.deployment = deployment;
settings.landers = [dev.number];
settings.arrayfile = arrayfile;
settings.bathyfile = bathysource;
settings.databases = cellfun(@(D) D.porpoisedB, landers, 'UniformOutput', false);
settings.clicksfiles = repmat({''}, 1, nl);  % '' where the database was used
for d = find(cellfun(@uses_clicksfile, landers))
    settings.clicksfiles{d} = landers{d}.clicksfile;
end
settings.tlims = tlims;
settings.depth = depth;
settings.headingcorrection = headingcorrection;
settings.reflatlon = reflatlon;
settings.landerxyz = landerxyz;             % [east north up] of each lander (m)
settings.landerlatlon = vertcat(dev.latlon);
settings.landerhpr = vertcat(dev.hpr);
settings.depthoffset = depthoffset;         % added to the bathymetry (m)
settings.clockprior = prior;
settings.clockline = clockline;             % offset0 (s) at t0 and rate (s/day) of each lander
settings.conventions = ['times are datenum on the first lander''s clock; clockoffset is lander - ' ...
    'first lander (s); positions are m east, north and up from reflatlon at the sea surface'];
settings.encounters = encounters;           % the encounters run this time

info.encounters = enc;
info.landers = rmfield(dev, {'data', 't', 'track', 'delays', 'tderr', 'bearing', 'slant', 'uvec'});
% the clicks of the tracks inside TLIMS on each lander, with their true
% bearings, for plots of the bearings against the localised tracks
info.clicks = struct('lander', {dev.number}, 't', {dev.t}, 'trackcode', ...
    cellfun(@(c, k) c(k), {dev.code}, cellfun(@(k) k(:), {dev.track}, 'UniformOutput', false), ...
    'UniformOutput', false), 'bearing', {dev.bearing}, 'slant', {dev.slant}, 'uvec', {dev.uvec});
info.clockline = clockline;
info.clockpass1 = pass1;
info.meshdata = meshdata;
info.settings = settings;
info.nostart = nostart;
info.outfolder = outfolder;
if ~opt.localise
    return
end

matfile = fullfile(outfolder, [name '_loctracks.mat']);
if exist(matfile, 'file') && ~isempty(loctracks)
    % keep the tracks of the encounters which were not run this time
    old = load(matfile);
    keep = old.loctracks(~ismember([old.loctracks.encounter], encounters));
    if ~isequal(fieldnames(keep), fieldnames(loctracks))
        keep = []; % saved by an older version of this function
    end
    loctracks = [keep, loctracks];
    if isfield(old, 'nostart') && ~isempty(old.nostart)
        codes = {enc(encounters).code};
        nostart = [old.nostart(~startsWith({old.nostart.code}, codes)), nostart];
    end
    [~, order] = sortrows([[loctracks.encounter]', [loctracks.datestart]']);
    loctracks = loctracks(order);
    info.nostart = nostart;
end
if ~isempty(loctracks)
    encounters = enc; %#ok<NASGU> the clock offsets and associations of every encounter
    save(matfile, 'loctracks', 'settings', 'encounters', 'nostart');
    fprintf('\nSaved %d tracks to %s\n', numel(loctracks), matfile);
    for q = unique({loctracks.startconstraint})
        fprintf('  %3d tracks started by %s\n', sum(strcmp({loctracks.startconstraint}, q{1})), q{1});
    end
    fprintf('  %3d fragments with no start location\n', numel(nostart));
else
    fprintf('\nNothing was localised\n');
end
if opt.savefigs
    fprintf('Figures saved in %s\n', outfolder);
end

end

%% ------------------------------------------------------------------------
function S = propagation_summary(props)
% type, time, sound speed and source of each propagation struct
S = struct('type', {}, 'time', {}, 'soundspeed', {}, 'source', {});
if isempty(props)
    return
end
if isstruct(props)
    props = num2cell(props);
end
for i = 1:numel(props)
    P = props{i};
    S(i).type = 'straight';
    if isfield(P, 'type'), S(i).type = P.type; end
    S(i).time = NaT;
    if isfield(P, 'time'), S(i).time = P.time; end
    S(i).soundspeed = P.soundspeed;
    S(i).source = '';
    if isfield(P, 'source'), S(i).source = P.source; end
end
end

%% ------------------------------------------------------------------------
function [P, name, c, delayfun] = encounter_propagation(props, t, soundspeed, match)
% the propagation of an encounter starting at T (datenum): the struct of
% PROPS closest in time, its description, the sound speed at the landers
% and the time delay function of the particle filter ([] for straight
% lines, which the particle filter does itself)
if isempty(props)
    P = straight_propagation(NaT, soundspeed);
else
    P = select_propagation(props, t, match);
end
c = P.soundspeed;
if isfield(P, 'type') && strcmp(P.type, 'raytrace')
    delayfun = propagation_delays(P);
    src = '';
    if isfield(P, 'source'), src = [P.source ' ']; end
    name = sprintf('ray traced, %s(%s), %.1f m/s at the landers', src, ...
        char(P.time, 'yyyy-MM-dd HH:mm'), c);
else
    delayfun = [];
    if isfield(P, 'time') && ~isnat(P.time)
        name = sprintf('straight line, %.1f m/s (%s)', c, char(P.time, 'yyyy-MM-dd HH:mm'));
    else
        name = sprintf('straight line, %.1f m/s', c);
    end
end
end

%% ------------------------------------------------------------------------
function M = platform_rotm(hpr)
% rotation of PAMGuard's array frame (bearing 0 along +y, z up) to east,
% north, up for a lander with heading, pitch and roll HPR (deg). It is what
% ROTATE_BEARINGS does to a bearing, applied to the axes of the frame, so
% the time delays of the rotated hydrophones point along the bearings
% LOCATEPLATFORM fitted HPR to.
[b, s] = locvec2angles(eye(3));
[~, ned] = rotate_bearings([b s], hpr);
M = [ned(:,2), ned(:,1), -ned(:,3)]';
end

function angles = pamguard_bearings(angles)
% click angles of the binary files to PAMGuard [bearing, slant angle]
% (rad), as CLKSTRUCT2BEARINGS
angles = [-wrapToPi(angles(:,1) - pi/2), angles(:,2)];
end

function T = load_tracks(data, deployment, porptypes, cachefolder, usecache)
% the clicks of the tracks of a deployment (events of type PORPTYPES which
% start inside the deployment) of a lander, from its porpoise database and
% binary store
% (LOAD_EVENT_CLICKS) or, if DATA.CLICKSFILE is given, from that .mat file:
%   t, angles, delays, tderr - time (datenum), angles (rad), time delays
%          (s) and time delay error (s) of each click
%   track - index of the track of each click
%   code, tracklims - label (the event comment, or 'event<UID>' if it has
%          none) and [start end] (datenum) of each track
%   hydrophones - [x y z] (m) of the hydrophones in PAMGuard's array frame
if uses_clicksfile(data)
    S = load(data.clicksfile, 'click_events', 'hydrophones');
    E = S.click_events;
    hydrophones = S.hydrophones;
    source = data.clicksfile;
else
    db = dir(data.porpoisedB);
    cachefile = fullfile(cachefolder, sprintf('tracks_%d_lander%d_dep%d.mat', data.serialnumber, ...
        data.landernumber, deployment));
    if usecache && exist(cachefile, 'file')
        q = load(cachefile);
        % the database has not changed since
        if isfield(q, 'T') && isfield(q.T, 'hydrophones') && q.dbdatenum == db.datenum && ...
                strcmp(q.dbfile, data.porpoisedB) && isfield(q, 'porptypes') && ...
                isequal(q.porptypes, porptypes)
            T = q.T;
            return
        end
    end
    fprintf('lander%d: loading tracks from %s (slow)\n', data.landernumber, db.name);
    E = load_event_clicks(data.porpoisedB, data.binaryfolder, [], [], 'waveforms', false, ...
        'verbose', false);
    hydrophones = read_pamguard_hydrophones(data.porpoisedB);
    source = data.porpoisedB;
end

% the tracks of this deployment: porpoise events starting inside it
indeployment = isfield(data, 'startTime') && isfield(data, 'endTime') && ...
    ~isempty(data.startTime) && ~isempty(data.endTime);
ok = false(numel(E), 1);
for k = 1:numel(E)
    ok(k) = ismember(strtrim(char(E(k).event_type)), porptypes) && ~isempty(E(k).date);
    if ok(k) && indeployment
        ok(k) = E(k).date >= datenum(data.startTime) && E(k).date < datenum(data.endTime);
    end
end
E = E(ok);
% a label for each track, for the printout and output only
codes = cell(numel(E), 1);
for k = 1:numel(E)
    codes{k} = strtrim(char(E(k).comment));
    if isempty(codes{k}) || strcmp(codes{k}, 'none')
        codes{k} = sprintf('event%d', E(k).eventUID);
    end
end
if isempty(codes)
    error('localiseporpoises:noTracks', ...
        'No %s events in deployment %d in %s - run CUMBIAH_MULTITRACK or mark the tracks first.', ...
        strjoin(porptypes, '/'), deployment, source);
end

% the clicks of every track
[t, angles, delays, tderr, track] = deal(cell(numel(E), 1));
for k = 1:numel(E)
    c = E(k).clicks(:);
    t{k} = [c.date]';
    angles{k} = cell2mat(arrayfun(@(x) reshape(x.angles(1:2), 1, 2), c, 'UniformOutput', false));
    delays{k} = cell2mat(arrayfun(@(x) x.timeDelays(:)', c, 'UniformOutput', false));
    % the error of the time delays from the SNR of the click (s)
    [~, err] = evalc('error_TDOA(c)');
    tderr{k} = cellfun(@(e) e(1), err(:));
    track{k} = repmat(k, numel(c), 1);
end
t = vertcat(t{:});
delays = vertcat(delays{:});
tderr = vertcat(tderr{:});
ok = ~isnan(t) & all(isfinite(delays), 2) & isfinite(tderr);
[T.t, order] = sort(t(ok));
keep = find(ok);
keep = keep(order);
angles = vertcat(angles{:});
track = vertcat(track{:});
T.angles = angles(keep,:);
T.delays = delays(keep,:);
T.tderr = tderr(keep);
T.track = track(keep);
T.code = codes;
T.tracklims = nan(numel(codes), 2);
for k = 1:numel(codes)
    tk = T.t(T.track == k);
    if ~isempty(tk)
        T.tracklims(k,:) = [tk(1) tk(end)];
    end
end
T.hydrophones = hydrophones;
if usecache && ~uses_clicksfile(data)
    dbdatenum = db.datenum; %#ok<NASGU>
    dbfile = data.porpoisedB; %#ok<NASGU>
    save(cachefile, 'T', 'dbdatenum', 'dbfile', 'porptypes');
end
end

function tf = uses_clicksfile(data)
% the clicks of the lander are in a .mat file, not its database and binary
% store
tf = isfield(data, 'clicksfile') && ~isempty(data.clicksfile);
end

function enc = find_array_encounters(dev, prior, gap)
% runs of tracks, on any lander, with no gap of more than GAP minutes
% between them. Only those with tracks on two or more landers are kept.
%   tlims - [start end] (datenum, reference lander's clock by PRIOR)
%   landers - index of the landers with tracks
%   tracks - the tracks of each lander (cell, one per lander)
nl = numel(dev);
iv = zeros(0, 4); % start, end, lander, track
for d = 1:nl
    n = size(dev(d).tracklims, 1);
    iv = [iv; dev(d).tracklims - prior(d)/86400, repmat(d, n, 1), (1:n)']; %#ok<AGROW>
end
iv = sortrows(iv(~isnan(iv(:,1)),:));
enc = struct('tlims', {}, 'landers', {}, 'tracks', {});
i = 1;
while i <= size(iv, 1)
    j = i;
    tend = iv(i,2);
    while j < size(iv, 1) && iv(j+1,1) <= tend + gap/1440
        j = j + 1;
        tend = max(tend, iv(j,2));
    end
    rows = iv(i:j,:);
    if numel(unique(rows(:,3))) > 1
        enc(end+1).tlims = [rows(1,1) tend]; %#ok<AGROW>
        enc(end).landers = unique(rows(:,3))';
        enc(end).tracks = arrayfun(@(d) rows(rows(:,3) == d, 4)', 1:nl, 'UniformOutput', false);
    end
    i = j + 1;
end
end

function C = comb_clocks(enc, dev, baseline, centre, follow, search, extent, opt)
% the clock of each lander from the reference lander in every encounter,
% from a comb filter between the click times of each pair of landers. The
% comb is run out to EXTENT seconds either side of CENTRE (one row per
% encounter, one column per lander), which gives its background, and its
% peak is looked for within SEARCH seconds of CENTRE. With FOLLOW the
% search moves with the offsets found: it is centred on the last offset
% found for the lander.
%   offset - lander - reference lander (s), NaN for a lander with no tracks
%   found  - the offset was found by the comb filter. If not it is CENTRE
%            (or the last offset found), moved no more than its pairs need
%   snr, peak - comb peak/background and click pairs in the peak of each
%            pair of landers, [lander x lander x encounter]
nl = numel(dev);
ne = numel(enc);
C.offset = nan(ne, nl);
C.found = false(ne, nl);
C.snr = nan(nl, nl, ne);
C.peak = nan(nl, nl, ne);
moved = zeros(1, nl);
for k = 1:ne
    present = enc(k).landers;
    centrek = centre(k,:) + moved;
    times = cell(1, nl);
    for d = present
        times{d} = dev(d).t(ismember(dev(d).track, enc(k).tracks{d})) - centrek(d)/86400;
    end
    % what is left of the offset of each pair, lander j - lander i
    M = zeros(0, nl);
    r = zeros(0, 1);
    w = zeros(0, 1);
    for i = present
        for j = present(present > i)
            [~, comb] = find_time_offset(times{i}, times{j}, 'maxOffset', extent, ...
                'smoothWin', 2*baseline(i,j)/opt.soundspeed + 0.005);
            near = find(abs(comb.lags) <= search);
            [peak, ip] = max(comb.smoothed(near));
            res = comb.lags(near(ip));
            % the background is the median count, which is 0 for a few
            % clicks: never less than one click pair
            C.snr(i,j,k) = peak/max(comb.background, 1);
            C.peak(i,j,k) = peak;
            if C.snr(i,j,k) >= opt.mincombsnr && peak >= opt.mincombpeak
                M(end+1,:) = 0; %#ok<AGROW>
                M(end,[i j]) = [-1 1];
                r(end+1,1) = res; %#ok<AGROW>
                w(end+1,1) = sqrt(peak); %#ok<AGROW>
            end
        end
    end
    % fit the clocks to the pairs with a clear peak. The reference lander
    % is 0. A lander joined to it through such pairs has its clock found
    residual = zeros(1, nl);
    found = false(1, nl);
    if ~isempty(r)
        residual(2:end) = lsqminnorm(w.*M(:,2:end), w.*r)';
        bins = conncomp(graph(M'*M ~= 0, 'omitselfloops'));
        found = bins == bins(1) & ismember(1:nl, present) & ismember(1, present);
    end
    found(1) = ismember(1, present);
    C.offset(k,present) = centrek(present) + residual(present);
    C.found(k,:) = found;
    if follow
        moved(found) = moved(found) + residual(found);
    end
end
end

function [offset0, rate] = robust_line(t, y)
% line y = offset0 + rate*t through points some of which are wrong: the
% Theil-Sen line, the median of the slopes between every pair of points.
% Points less than half a day apart say nothing about the slope.
rate = 0;
if numel(t) >= 3
    [i, j] = find(triu(abs(t - t') > 0.5));
    if ~isempty(i)
        rate = median((y(j) - y(i))./(t(j) - t(i)));
    end
end
offset0 = median(y - rate*t);
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

function res = tracks2res(t, bearing, clicktrack, ntracks, windowlen)
% tracks read from a database as the output of TRACK_BEARINGS, as far as
% ASSOCIATE_TRACKS uses it: the bearing of a track is the mean bearing of
% its clicks in windows of WINDOWLEN seconds
res.params.windowLen = windowlen;
res.isEcho = false(numel(t), 1);
res.clickTrack = clicktrack;
res.tracks = struct('tnum', cell(1, ntracks), 'bearing', [], 'nClicks', 0);
for k = 1:ntracks
    in = clicktrack == k;
    if ~any(in)
        % a track with no clicks left: at no time, so it overlaps nothing
        res.tracks(k).tnum = -inf;
        res.tracks(k).bearing = 0;
        continue
    end
    tk = t(in);
    [~, ~, bin] = unique(floor((tk - tk(1))*86400/windowlen));
    res.tracks(k).tnum = accumarray(bin, tk, [], @mean);
    res.tracks(k).bearing = accumarray(bin, bearing(in), [], ...
        @(b) atan2d(mean(sind(b)), mean(cosd(b))));
    res.tracks(k).nClicks = sum(in);
end
end

function groups = join_tracks(edges, first, ed)
% associations from the tracks joined between pairs of landers: the tracks
% connected to each other through any pair. Lettered in time order.
%   tracks - the tracks of the association on each lander (cell, one per
%            lander, index into the tracks of the encounter)
nl = numel(ed);
groups = struct('tracks', {}, 'letters', {}, 'tstart', {});
if isempty(edges)
    return
end
bins = conncomp(graph(edges(:,1), edges(:,2), [], first(end)));
for b = unique(bins(unique(edges(:))))
    nodes = find(bins == b);
    g = numel(groups) + 1;
    groups(g).tstart = inf;
    for d = 1:nl
        groups(g).tracks{d} = nodes(nodes > first(d) & nodes <= first(d+1)) - first(d);
        if ~isempty(groups(g).tracks{d})
            groups(g).tstart = min(groups(g).tstart, ...
                min(ed(d).clktimes(ismember(ed(d).clicktrack, groups(g).tracks{d}))));
        end
    end
end
[~, order] = sort([groups.tstart]);
groups = groups(order);
for g = 1:numel(groups)
    groups(g).letters = [char('A' + floor((g - 1)/26)), char('A' + mod(g - 1, 26))];
end
end

function rows = match_rows(times, window)
% one row per click of an animal: ROWS(r,q) is the index of the click of
% lander q in row r, 0 if it has none. Clicks on different landers within
% WINDOW seconds of each other share a row. TIMES is a cell array of the
% sorted click times (datenum) of each lander.
nq = numel(times);
rows = zeros(0, nq);
rowtime = zeros(0, 1);
for q = 1:nq
    n = numel(times{q});
    i1 = zeros(0, 1);
    i2 = zeros(0, 1);
    if ~isempty(rowtime)
        [i1, i2] = match_clicks(rowtime, times{q}, window);
    end
    rows(i1,q) = i2;
    new = setdiff((1:n)', i2);
    rows = [rows; zeros(numel(new), nq)]; %#ok<AGROW>
    rows(end-numel(new)+1:end, q) = new;
    [rowtime, order] = sort([rowtime; times{q}(new)]);
    rows = rows(order,:);
end
end

function [i1, i2] = match_clicks(t1, t2, window)
% indices of the clicks of two devices (times t1, t2, datenum, sorted)
% within window seconds of each other; each click is matched once, the
% closest pairs first
i1 = zeros(0, 1);
i2 = zeros(0, 1);
if numel(t2) < 2
    return
end
near = interp1(t2, (1:numel(t2))', t1, 'nearest', 'extrap');
dtm = abs(t2(near) - t1)*86400;
cand = find(dtm <= window);
[~, order] = sort(dtm(cand));
used = false(size(t2));
for i = cand(order)'
    if ~used(near(i))
        used(near(i)) = true;
        i1(end+1, 1) = i; %#ok<AGROW>
        i2(end+1, 1) = near(i); %#ok<AGROW>
    end
end
[i1, order] = sort(i1);
i2 = i2(order);
end

function fragments = fragment_tracks(timessrt, timedelaysobs, timedelayserr, hydrophonesgeo, ...
    maxtimegap, minclicks, minlanderclicks)
% break the input of the particle filter into fragments at gaps of more
% than MAXTIMEGAP seconds, as FRAGMENTTRACKS. FRAGMENTTRACKS drops a
% fragment unless every device has clicks in it, which with three landers
% would lose the animals heard on two. Here a fragment keeps the landers
% with at least MINLANDERCLICKS clicks in it and needs two of them;
% COLUMNS says which they are. It also needs MINCLICKS clicks and more than
% one click a second.
minclickrate = 1; % clicks per second
fragments = struct('timessrt', {}, 'timedelaysobs', {}, 'timedelayserr', {}, ...
    'hydrophonesgeo', {}, 'columns', {});
has = ~cellfun(@isempty, timedelaysobs);
breaks = [0; find(diff(timessrt) > maxtimegap); numel(timessrt)];
for i = 1:numel(breaks) - 1
    r = (breaks(i) + 1:breaks(i+1))';
    cols = find(sum(has(r,:), 1) >= minlanderclicks);
    if numel(cols) < 2
        continue
    end
    r = r(any(has(r,cols), 2));
    if numel(r) < minclicks || numel(r)/(timessrt(r(end)) - timessrt(r(1))) <= minclickrate
        continue
    end
    fragments(end+1).timessrt = timessrt(r); %#ok<AGROW>
    fragments(end).timedelaysobs = timedelaysobs(r,cols);
    fragments(end).timedelayserr = timedelayserr(r,cols);
    fragments(end).hydrophonesgeo = hydrophonesgeo(r,cols);
    fragments(end).columns = cols;
end
end

function [meshdata, source] = seabed_mesh(bathyfile, reflatlon, lim, flatdepth)
% the seabed as x, y and z meshes (m east, north and up of REFLATLON) out
% to LIM, from the bathymetry LOCATE_ARRAY saved. The grid of that is
% square in UTM, a few degrees off true north, so it is interpolated onto
% an east-north grid; outside it the nearest depth is used. With no
% bathymetry file the seabed is flat at FLATDEPTH.
[meshdata.x, meshdata.y] = meshgrid(linspace(-lim, lim, 2*ceil(lim/10) + 1));
if ~isfile(bathyfile)
    warning('localiseporpoises:noBathymetry', ...
        'No bathymetry file %s - using a flat seabed at %.1f m.', bathyfile, -flatdepth);
    meshdata.z = repmat(flatdepth, size(meshdata.x));
    source = 'flat';
    return
end
B = load(bathyfile, 'bathy');
[~, bx, by] = latLong2meters(reflatlon(1), reflatlon(2), B.bathy.lat, B.bathy.lon);
ok = ~isnan(B.bathy.depth);
F = scatteredInterpolant(bx(ok), by(ok), B.bathy.depth(ok), 'linear', 'nearest');
meshdata.z = F(meshdata.x, meshdata.y);
source = bathyfile;
end

function plot_clocks(tmid, pass1, pass2, expected, dev)
% the clock offset of each lander from the reference lander in every
% encounter: crosses the first pass, the line fitted to them, and circles
% the second pass, filled where the comb filter found the offset and open
% where the line was used
cols = lines(numel(dev));
t = datetime(tmid, 'ConvertFrom', 'datenum');
hold on
h = gobjects(0);
for d = 2:numel(dev)
    ok = ~isnan(pass2.offset(:,d));
    f1 = pass1.found(:,d);
    f2 = pass2.found(:,d);
    h(end+1) = plot(t, expected(:,d), '-', 'Color', cols(d,:)); %#ok<AGROW>
    plot(t(f1), pass1.offset(f1,d), 'x', 'Color', cols(d,:), 'MarkerSize', 7);
    plot(t(ok & f2), pass2.offset(ok & f2,d), 'o', 'Color', cols(d,:), ...
        'MarkerFaceColor', cols(d,:), 'MarkerSize', 4);
    plot(t(ok & ~f2), pass2.offset(ok & ~f2,d), 'o', 'Color', cols(d,:), ...
        'MarkerFaceColor', 'w', 'MarkerSize', 4);
end
hold off
grid on
ylabel(sprintf('Clock offset from %s (s)', dev(1).name));
legend(h, {dev(2:end).name}, 'Location', 'best');
title('x first pass, line fitted to it; o second pass (filled = comb filter, open = the line)');
end

function plot_association(ed, groups, present)
% the click bearings of an encounter on each lander against time, coloured
% by association. Clicks of tracks not matched to another lander are grey.
cols = lines(max(numel(groups), 1));
tl = tiledlayout(numel(present), 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax = gobjects(0);
for d = present
    ax(end+1) = nexttile(tl); %#ok<AGROW>
    hold on
    t = datetime(ed(d).clktimes, 'ConvertFrom', 'datenum');
    matched = false(size(t));
    for g = 1:numel(groups)
        in = ismember(ed(d).clicktrack, groups(g).tracks{d});
        matched = matched | in;
    end
    plot(t(~matched), ed(d).bearings(~matched), '.', 'Color', [0.7 0.7 0.7], 'MarkerSize', 4);
    for g = 1:numel(groups)
        in = find(ismember(ed(d).clicktrack, groups(g).tracks{d}));
        if isempty(in)
            continue
        end
        plot(t(in), ed(d).bearings(in), '.', 'Color', cols(g,:), 'MarkerSize', 6);
        text(t(in(1)), ed(d).bearings(in(1)), groups(g).letters, 'Color', cols(g,:), ...
            'FontWeight', 'bold', 'VerticalAlignment', 'bottom');
    end
    hold off
    ylim([-180 180])
    yticks(-180:90:180)
    grid on
    ylabel(sprintf('%s (%s)', ed(d).name, char(176)));
end
linkaxes(ax, 'x');
end
