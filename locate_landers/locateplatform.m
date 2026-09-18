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
%bearing difference
validclk = ~isnan(clkangdiff);

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
[locationfine, hprfinal, chi2fine, chi2surffine] = ...
    grdsrch_pos_hpr(clkgeobearings(validclk, :), srcclklocations(validclk, :), location, ...
    'gridspacing', opt.finegridspacing, 'gridlims', opt.finegridlims, ...
    'headinglims', headingoffset + opt.fineanglelims, 'pitchlims', opt.fineanglelims, ...
    'rolllims', opt.fineanglelims, 'anglestep', opt.fineanglestep, ...
    'searchtype', 'all', 'pretext', 'Fine search ');

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
