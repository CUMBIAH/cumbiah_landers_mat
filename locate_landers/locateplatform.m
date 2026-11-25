function results = locateplatform(data, varargin)
%LOCATEPLATFORM Locate a seabed platform and its orientation from boat calibrations.
%
%   RESULTS = LOCATEPLATFORM(DATA) works out where a CUMBIAH lander actually
%   came to rest on the seabed, and which way up and round it is lying, from
%   the vessel calibration lines run over it on the day it was deployed. DATA
%   is one deployment record as returned by GETLANDERPATHS - it supplies
%   the database, the binary store, the vessel GPS track and the drop
%   position, so a lander is located by passing its record straight in:
%
%       data = getlanderpaths(8688, datetime(2024,10,6));
%       results = locateplatform(data);
%
%   This function draws nothing. Everything the plots need is returned in
%   RESULTS - see LOCATE_PLATFORM for the figures that go with it.
%
%   HOW IT WORKS. The boat runs lines over the lander making a noise, and the
%   4 channel SoundTrap gives a bearing to that noise for every click. The
%   boat's own GPS says where the noise was made. A grid search then finds
%   the position that best explains the bearings, in three passes:
%
%     1. A coarse position search, repeated over a range of clock offsets,
%        because the SoundTrap's real time clock drifts against the boat GPS
%        and the offset that gives the lowest chi2 is taken as the true one.
%     2. The heading, as the circular mean of the difference between the
%        click bearings and the true bearings to the boat. The bearings are
%        geo referenced assuming the platform lies flat and points north, so
%        that difference is the heading.
%     3. A fine search over position, heading, pitch and roll together,
%        around the coarse answers.
%
%   RESULTS is a struct with the fields:
%
%       landernumber    - lander this was, from DATA
%       deployment      - deployment number, from DATA
%       location        - [lat lon] from the coarse grid search, or SETLOCATION
%       chi2            - chi2 of that location
%       rtctimeoffset   - SoundTrap clock offset that fitted best, seconds
%       rtcoffset       - every clock offset tried, seconds
%       chi2offsets     - chi2 of the best position at each of those offsets
%       chi2surf        - coarse chi2 surface at RTCTIMEOFFSET, empty when
%                         SETLOCATION is used
%       headingoffset   - platform heading, degrees
%       headingstd      - circular standard deviation of the heading, degrees
%       clkangdiff      - per click bearing difference the heading is the
%                         circular mean of, degrees
%       validclk        - clicks that fell inside the GPS track, and so have
%                         a bearing difference at all
%       locationfine    - [lat lon] from the fine search
%       hprfinal        - [heading pitch roll] from the fine search, degrees
%       chi2fine        - chi2 of the fine search
%       chi2surffine    - fine chi2 surface
%       clickbearings   - the thinned click bearings actually used, as
%                         [datenum horizontal vertical] in degrees
%       clkgeobearings  - those bearings in radians, as passed to the search
%       clkgeobearingsfinal - the same with the full HPRFINAL rotation applied
%       srcclklocations - [datenum lat lon depth] of the boat for each click
%       srcbearings     - true [horizontal vertical] bearings from LOCATION
%                         to the boat, degrees
%       droplocation    - [lat lon] the lander was dropped at, from DATA
%       sqlitedB        - database the clicks were read from
%       binaryfolder    - binary day folder the clicks were read from
%
%   Name-value options:
%
%       'depth'        - depth of the platform, m. Default 17.
%       'binaryday'    - datetime of the calibration day, used to pick the
%                        day folder inside DATA.BINARYFOLDER. Default is the
%                        deployment day, because the calibration lines were
%                        always run straight after the landers went down. The
%                        binary store holds every deployment of a lander, so
%                        this is what narrows it to the calibration.
%       'database'     - database to read the calibration events from.
%                        Default DATA.SQLITEDB, the annotated one. Landers
%                        whose annotation has not reached the calibration
%                        events yet hold them only in DATA.RAWSQLITEDB, and
%                        that is used automatically, with a warning, when the
%                        annotated database turns out to have none.
%       'eventtype'    - PAMGuard event type holding the calibration clicks.
%                        Default 'bc'.
%       'searchtype'   - 'bearing', 'slant' or 'all'. Default 'slant'.
%       'rtcoffset'    - clock offsets to try, seconds. Default -10:10.
%       'gridsize'     - coarse grid size. Default 50.
%       'gridlims'     - coarse grid limits in metres, relative to GRIDCENTER.
%                        Either [min max], used for both north and east, or
%                        [northmin northmax eastmin eastmax]. e.g. [-200 200]
%                        searches a 400 m square. The grid still has GRIDSIZE
%                        points along each side. Default is empty and the
%                        limits are decided by the source locations.
%       'gridcenter'   - [lat lon] in decimal degrees that GRIDLIMS are
%                        measured from. Required when GRIDLIMS is set.
%       'maxchi2'      - chi2 ceiling for the coarse search. Default 2e6.
%       'maxbearings'  - bearings kept per second. Default 5.
%       'finegridspacing', 'finegridlims', 'fineanglelims', 'fineanglestep'
%                      - the fine search grid: 1 m steps over +/-30 m, and
%                        1 degree steps over +/-10 degrees around the coarse
%                        heading. Note the fine search uses the raw bearings
%                        and searches heading around HEADINGOFFSET rather
%                        than pre rotating them: heading, pitch and roll are
%                        a single rotation applied in that order, so rotating
%                        by the heading first and then looking for a pitch
%                        and roll on top would not give the true pitch and
%                        roll of the platform.
%       'maxrange'     - only clicks with the boat within this horizontal
%                        range (m) of the lander are used for the heading
%                        and the fine search. The range is from the coarse
%                        location, then once more from the fine location.
%                        Close passes give steep slants, where refraction
%                        and the seabed echo of the boat noise do not bias
%                        the slant angle. Default inf (every click).
%       'propagation'  - a ray traced propagation struct (MAKE_PROPAGATION_TABLE)
%                        whose table reaches the boat ranges. The fine
%                        search then predicts the slant the boat noise
%                        arrives from through that sound speed profile
%                        instead of a straight line, so refraction is
%                        allowed for. The table's hydrophone depth should
%                        be DEPTH. Default [] (straight lines).
%       'propoffset'   - distances (m) the boat noise is made astern of the
%                        GPS antenna, along the boat's track, to try in the
%                        fine search: the cavitation comes from the
%                        propeller, not the antenna. The fine search is run
%                        at each one and the one with the lowest chi2 kept.
%                        Where the boat is going slower than 0.5 m/s its
%                        direction is unknown and it is not shifted.
%                        Default 0 (the GPS position).
%       'setlocation'  - [lat lon] to force as the coarse location, skipping
%                        the coarse position search. The clock offset is
%                        still fitted, as the offset in RTCOFFSET giving the
%                        lowest chi2 at this location. Default [] (search).
%
%   See also LOCATE_PLATFORM, GETLANDERPATHS, GETLANDERDEPLOYMENTINFO,
%   GRDSRCH_POS, GRDSRCH_POS_HPR, INTERPSRCLOC.

% ---- options -----------------------------------------------------------
p = inputParser;
p.addParameter('depth', 17);
p.addParameter('binaryday', []);
p.addParameter('database', '');
p.addParameter('eventtype', 'bc');
p.addParameter('searchtype', 'slant');
p.addParameter('rtcoffset', -10:0.5:10);
p.addParameter('gridsize', 100);
p.addParameter('gridlims', [], @(x) isempty(x) || (isnumeric(x) && any(numel(x)==[2 4])));
p.addParameter('gridcenter', [], @(x) isempty(x) || (isnumeric(x) && numel(x)==2));
p.addParameter('maxchi2', 2000000);
p.addParameter('maxbearings', 5);
p.addParameter('finegridspacing', 1);
p.addParameter('finegridlims', [-30 30]);
p.addParameter('fineanglelims', [-10 10]);
p.addParameter('fineanglestep', 0.5);
p.addParameter('maxrange', inf);
p.addParameter('propagation', []);
p.addParameter('propoffset', 0);
p.addParameter('setlocation', [], @(x) isempty(x) || (isnumeric(x) && numel(x)==2));
p.parse(varargin{:});
opt = p.Results;
opt.setlocation = opt.setlocation(:)';

% A custom coarse grid is given in metres around a centre point, so work out
% its latitude and longitude limits once here. Empty means the limits come
% from the source locations at each clock offset.
customlatlims = [];
customlonlims = [];
if ~isempty(opt.gridlims)
    if isempty(opt.gridcenter)
        error('locateplatform:noGridCenter', ...
            '''gridcenter'' ([lat lon]) is required when ''gridlims'' is set.');
    end
    gridlims = opt.gridlims(:)';
    if numel(gridlims)==2
        gridlims = [gridlims gridlims];
    end
    if gridlims(1)>=gridlims(2) || gridlims(3)>=gridlims(4)
        error('locateplatform:badGridLims', ...
            '''gridlims'' must be increasing, [min max] or [northmin northmax eastmin eastmax].');
    end
    customlatlims = meters2LatLong(opt.gridcenter(1), opt.gridcenter(2), gridlims([1 2]), [0 0]);
    [~, customlonlims] = meters2LatLong(opt.gridcenter(1), opt.gridcenter(2), [0 0], gridlims([3 4]));
elseif ~isempty(opt.gridcenter)
    warning('locateplatform:gridCenterIgnored', ...
        '''gridcenter'' is ignored because ''gridlims'' is not set.');
end

% the slant angle model of the fine search: straight lines, or ray traced
slantfun = [];
if ~isempty(opt.propagation) && isfield(opt.propagation, 'type') && strcmp(opt.propagation.type, 'raytrace')
    P = opt.propagation;
    if max(P.ranges) < 1000
        warning('locateplatform:shortTable', ...
            'The propagation table only reaches %.0f m; boat clicks further away use its last range.', max(P.ranges));
    end
    F = griddedInterpolant({P.ranges(:), P.depths(:)}, P.slant, 'linear', 'nearest');
    % DZ is the height of the source above the platform; its depth in the
    % table is the same height above the table's hydrophones
    slantfun = @(r, dz) deg2rad(F(r(:), min(max(P.hdepth - dz(:), P.depths(1)), P.depths(end))));
end

% ---- unpack the deployment record --------------------------------------
if isempty(data.landernumber)
    error('locateplatform:noDeployment', ...
        ['DATA holds no deployment - GETLANDERPATHS found no lander for ' ...
         'that serial number and time.']);
end

% The binary store holds every deployment of this lander, so narrow it to
% the day of the calibration.
calibday = opt.binaryday;
if isempty(calibday)
    calibday = data.startTime;
end
binaryfolder = fullfile(data.binaryfolder, char(calibday, 'yyyyMMdd'));
if ~isfolder(binaryfolder)
    error('locateplatform:noBinaryDay', ...
        'No binary data for %s in %s.', char(calibday, 'yyyy-MM-dd'), data.binaryfolder);
end

dropgpsloc = data.droplocation;
depthdata  = opt.depth;

% ---- the clicks --------------------------------------------------------
[clicks, sqlitedB] = loadcalibrationclicks(data, binaryfolder, opt);

%sort the clicks and angles by time
[~, index] = sort([clicks.date]);
clicks = clicks(index);
clickbearingsall = clkstruct2bearings(clicks);

%thin the bearings to a maximum of 5 per second, evenly spread through
%each second
clickbearings = decimate_bearings(clickbearingsall, opt.maxbearings);

clkgeobearings = clickbearings(:, [2 3]);
clkgeobearings = deg2rad(clkgeobearings);

%maybe need to roate by soundtrap pitch here.

% ---- the boat track ----------------------------------------------------
%needs to load time, lat and long
gpsData = load(data.gpsfile);
gpsData = [datenum(gpsData.gpsdata.time), gpsData.gpsdata.latitude, gpsData.gpsdata.longitude];
gpsData(1,:) = []; %remove NAM

% ---- coarse search over position and clock offset ----------------------
rtcoffset = opt.rtcoffset;
locations = nan(length(rtcoffset), 2);
chi2      = nan(1, length(rtcoffset));
chi2surfdata = cell(1, length(rtcoffset));

for i = 1:length(rtcoffset)

    %we offset the GPS locations by the time offset
    gpsdatartc = gpsData;
    gpsdatartc(:,1) = gpsData(:,1) + rtcoffset(i)/60/60/24;

    %need to make sure all click bearings are within GPS time bounds
    index = clickbearings(:,1)>min( gpsdatartc(:,1)) & clickbearings(:,1)<max( gpsdatartc(:,1));

    srcclklocations = interpsrcloc(clickbearings(index,1), gpsdatartc, depthdata);

    if ~isempty(opt.setlocation)
        %the location is set so there is no position search - just the chi2
        %of that location at this clock offset
        locations(i,:) = opt.setlocation;
        chi2(i) = st_loc_chi2(opt.setlocation, srcclklocations(:,[1 2]), ...
            srcclklocations(:,3), clkgeobearings(index, :), opt.searchtype);
        continue;
    end

    % grid search stuff.
    pretxt = ['Time offset: ' num2str(rtcoffset(i)) 's ' num2str(i) ' of ' num2str(length(rtcoffset)) ' '];

    %the grid covers the source locations unless a custom grid was set
    if isempty(customlatlims)
        latlims = minmax(srcclklocations(:,1));
        lonlims = minmax(srcclklocations(:,2));
    else
        latlims = customlatlims;
        lonlims = customlonlims;
    end

    % now use a grid search to calculate the location.
    [locations(i,:), chi2(i), chi2surf] = ...
        grdsrch_pos(clkgeobearings(index, :), srcclklocations, 'maxchi2', opt.maxchi2, ...
        'gridsize', opt.gridsize, 'lonlims', lonlims, 'latlims', latlims,...
        'searchtype', opt.searchtype, 'pretext', pretxt);

    chi2surfdata{i} = chi2surf;

end

[minchi2, index] = min(chi2);
chi2surf = chi2surfdata{index};
location = locations(index,:);
rtctimeoffset = rtcoffset(index);


%of course have to redo the source locations or the last location is used-
gpsdatartc(:,1) = gpsData(:,1) + rtctimeoffset/60/60/24;
srcclklocations = interpsrcloc(clickbearings(:,1), gpsdatartc, depthdata);
srcclklocationst = [clickbearings(:,1) srcclklocations];

% ---- heading of the platform -------------------------------------------
% The bearings are geo referenced assuming the platform is lying flat and
% pointing north, so the mean difference between the click bearings and the
% true bearings to the boat is the heading of the platform.
srcbearings = srclocbearings(location, srcclklocationst);

clkangdiff = zeros(length(clkgeobearings), 1); %pre allocate
srcloctimes = srcclklocationst(:,1);
for i = 1:length(clkgeobearings)

   [~, srcindex] = min(abs(srcloctimes-clickbearings(i,1)));

   clkangdiff(i) = angdiffd(rad2deg(clkgeobearings(i,1)), srcbearings(srcindex,1));
end

%clicks which fall outside the GPS data have no source location and so no
%bearing difference. With MAXRANGE only the close passes are used.
srcrange = boatrange(location, srcclklocationst);
validclk = ~isnan(clkangdiff) & srcrange <= opt.maxrange;
if sum(validclk) < 20
    error('locateplatform:fewClicks', 'Only %d clicks within %g m of the lander.', ...
        sum(validclk), opt.maxrange);
end

%use a circular mean so the wrap around at +/-180 degrees does not bias the
%heading, and a circular standard deviation to show how well it fits
meanvec = mean(exp(1i*deg2rad(clkangdiff(validclk))));
headingoffset = rad2deg(angle(meanvec));
headingstd = rad2deg(sqrt(-2*log(abs(meanvec))));

% ---- fine grid search over position, heading, pitch and roll -----------
% A 1m grid +/-30m around the coarse location, allowing the orientation of
% the platform to move a few degrees around the heading found above.
% Note that the search uses the raw bearings and searches the heading
% around HEADINGOFFSET. Heading, pitch and roll are a single rotation
% applied in that order, so rotating by the heading first and then
% searching for a pitch and roll on top of it would not give the true
% pitch and roll of the platform.
% The boat noise is made at the propeller, astern of the GPS antenna, so
% with PROPOFFSET the fine search is run with the source moved astern along
% the boat's track by each offset and the best fit kept.
fineargs = {'gridspacing', opt.finegridspacing, 'gridlims', opt.finegridlims, ...
    'headinglims', headingoffset + opt.fineanglelims, 'pitchlims', opt.fineanglelims, ...
    'rolllims', opt.fineanglelims, 'anglestep', opt.fineanglestep, ...
    'searchtype', 'all', 'slantfun', slantfun};
boatdir = boat_direction(clickbearings(:,1), gpsdatartc);
propoffsets = opt.propoffset(:)';
chi2prop = nan(size(propoffsets));
chi2fine = inf;
srcclklocations0 = srcclklocations;
for k = 1:numel(propoffsets)
    srcloc = shift_astern(srcclklocations0, boatdir, propoffsets(k));
    srclocst = [clickbearings(:,1) srcloc];
    pre = sprintf('Fine search (propeller %g m astern) ', propoffsets(k));
    valid = validclk;
    [lf, hf, cf, sf] = grdsrch_pos_hpr(clkgeobearings(valid, :), srcloc(valid, :), location, ...
        fineargs{:}, 'pretext', pre);
    %with MAXRANGE, the clicks are picked again by their range from the fine
    %location and the fine search is run once more if that changes them
    if isfinite(opt.maxrange)
        valid2 = ~isnan(clkangdiff) & boatrange(lf, srclocst) <= opt.maxrange;
        if ~isequal(valid2, valid)
            valid = valid2;
            [lf, hf, cf, sf] = grdsrch_pos_hpr(clkgeobearings(valid, :), srcloc(valid, :), location, ...
                fineargs{:}, 'pretext', [pre '(again) ']);
        end
    end
    chi2prop(k) = cf;
    if cf < chi2fine
        locationfine = lf; hprfinal = hf; chi2fine = cf; chi2surffine = sf;
        validfine = valid;
        srcclklocations = srcloc;
        srcclklocationst = srclocst;
        propoffset = propoffsets(k);
    end
end
validclk = validfine;

%and the bearings with the full orientation applied
clkgeobearingsfinal = rotate_bearings(clkgeobearings, hprfinal);

% ---- results -----------------------------------------------------------
results = struct();
results.landernumber        = data.landernumber;
results.deployment          = data.deployment;
results.location            = location;
results.chi2                = minchi2;
results.rtctimeoffset       = rtctimeoffset;
results.rtcoffset           = rtcoffset;
results.chi2offsets         = chi2;
results.chi2surf            = chi2surf;
results.headingoffset       = headingoffset;
results.headingstd          = headingstd;
results.clkangdiff          = clkangdiff;
results.validclk            = validclk;
results.locationfine        = locationfine;
results.hprfinal            = hprfinal;
results.chi2fine            = chi2fine;
results.chi2surffine        = chi2surffine;
results.clickbearings       = clickbearings;
results.clkgeobearings      = clkgeobearings;
results.clkgeobearingsfinal = clkgeobearingsfinal;
results.srcclklocations     = srcclklocationst;
results.srcbearings         = srcbearings;
results.droplocation        = dropgpsloc;
results.sqlitedB            = sqlitedB;
results.binaryfolder        = binaryfolder;
results.maxrange            = opt.maxrange;
results.propoffset          = propoffset;       % m astern of the GPS, the best of PROPOFFSETS
results.propoffsets         = propoffsets;
results.chi2propoffsets     = chi2prop;         % chi2 of the fine search at each
results.propagation         = 'straight line';
if ~isempty(slantfun)
    results.propagation = sprintf('ray traced, %s', opt.propagation.source);
end

end

% ------------------------------------------------------------------------
function [clicks, sqlitedB] = loadcalibrationclicks(data, binaryfolder, opt)
%LOADCALIBRATIONCLICKS The calibration event clicks, from whichever database has them.
%   The annotated database is the one to analyse from, but annotation has not
%   reached the calibration events on every lander yet - lander 2's
%   calibration events, for instance, exist only in the database PAMGuard
%   wrote. Rather than silently returning no clicks, fall back to the raw
%   database and say so.

if ~isempty(opt.database)
    sqlitedB = opt.database;
    clicks = import_clk_train(sqlitedB, binaryfolder, 'eventtype', opt.eventtype);
    return;
end

%lander 3 has no annotated database at all yet, so only read it if it exists
sqlitedB = data.sqlitedB;
clicks = [];
if isfile(sqlitedB)
    clicks = import_clk_train(sqlitedB, binaryfolder, 'eventtype', opt.eventtype);
end
if ~isempty(clicks)
    return;
end

if strcmp(data.rawsqlitedB, sqlitedB) || ~isfile(data.rawsqlitedB)
    error('locateplatform:noCalibrationClicks', ...
        'No ''%s'' events on %s in %s.', opt.eventtype, ...
        char(data.startTime, 'yyyy-MM-dd'), sqlitedB);
end

warning('locateplatform:usingRawDatabase', ...
    ['No ''%s'' events in the annotated database for lander %d (or no annotated database), falling back ' ...
     'to the database PAMGuard wrote:\n  %s'], ...
    opt.eventtype, data.landernumber, data.rawsqlitedB);

sqlitedB = data.rawsqlitedB;
clicks = import_clk_train(sqlitedB, binaryfolder, 'eventtype', opt.eventtype);

if isempty(clicks)
    error('locateplatform:noCalibrationClicks', ...
        'No ''%s'' events on %s in either database for lander %d.', ...
        opt.eventtype, char(data.startTime, 'yyyy-MM-dd'), data.landernumber);
end

end

% ------------------------------------------------------------------------
function u = boat_direction(t, gps)
%BOAT_DIRECTION Unit vector [north east] of the boat's travel at each time T
%(datenum) from the GPS track GPS [datenum lat lon], over +/-10 s. NaN where
%the boat is going slower than 0.5 m/s, when its direction is unknown.
dt = 10/86400;
lat1 = interp1(gps(:,1), gps(:,2), t - dt); lon1 = interp1(gps(:,1), gps(:,3), t - dt);
lat2 = interp1(gps(:,1), gps(:,2), t + dt); lon2 = interp1(gps(:,1), gps(:,3), t + dt);
dn = (lat2 - lat1)*111320;
de = (lon2 - lon1)*111320.*cosd((lat1 + lat2)/2);
v = hypot(dn, de);
u = [dn, de]./v;
u(v/20 < 0.5 | isnan(v), :) = NaN;
end

% ------------------------------------------------------------------------
function src = shift_astern(src, u, d)
%SHIFT_ASTERN Move source locations [lat lon depth] D metres astern along
%the boat's direction U [north east]. Where U is NaN they are not moved.
if d == 0
    return
end
ok = ~any(isnan(u), 2);
src(ok,1) = src(ok,1) - d*u(ok,1)/111320;
src(ok,2) = src(ok,2) - d*u(ok,2)./(111320*cosd(src(ok,1)));
end

% ------------------------------------------------------------------------
function r = boatrange(location, srclocations)
%BOATRANGE Horizontal range (m) from LOCATION [lat lon] to the boat for every
%source location [datenum lat lon depth]; NaN where there is none.
r = nan(size(srclocations, 1), 1);
for i = 1:size(srclocations, 1)
    if ~any(isnan(srclocations(i, 2:3)))
        r(i) = latLong2meters(location(1), location(2), srclocations(i,2), srclocations(i,3));
    end
end
end

% ------------------------------------------------------------------------
function bearing = srclocbearings(location, srclocations)
%SRCLOCBEARINGS True bearings from the platform to the boat, degrees.
%   [horizontal vertical] for every source location, where SRCLOCATIONS is
%   [datenum lat lon depth]. This is the same calculation PLOT_CLK_SRC_BEARINGS
%   does before it draws - it is repeated here so that the heading can be
%   worked out without opening a figure.

bearing = zeros(length(srclocations(:,2)), 2);
for i = 1:length(srclocations(:,2))
    bearing(i,1) = latLong2bearing(location(1), location(2), ...
        srclocations(i,2), srclocations(i,3), 'atan');

    range = latLong2meters(location(1), location(2), ...
        srclocations(i,2), srclocations(i,3));

    bearing(i,2) = atand(srclocations(i,4)/range);
end

end
