function T = cumbiahlandertable(refresh)
%CUMBIAHLANDERTABLE Every CUMBIAH Denmark lander deployment, from the spreadsheet.
%
%   T = CUMBIAHLANDERTABLE() returns a struct array with one element per
%   (lander, deployment) pair actually deployed, read out of the lander
%   settings spreadsheet in the Denmark folder. Each element carries the
%   fields listed in CUMBIAHDATADEFAULTS except the data paths, which are
%   added by GETDANISHLANDERPATHS.
%
%   T = CUMBIAHLANDERTABLE(true) forces a re-read. The spreadsheet is
%   otherwise read once and cached, because reading it is slow (it is 30 MB)
%   and the lookup functions call this on every query.
%
%   There are three deployments of the nine landers at the Danish site:
%
%       1  Oct 24   deployed 2024-10-05, all nine landers. Landers 1, 5, 7
%                   and 8 were recovered 2025-02-02 and redeployed the next
%                   day; the other five stayed down until 2025-03-29.
%       2  Feb 25   deployed 2025-02-03, landers 1, 5, 7 and 8 only.
%       3  June 25  deployed 2025-06-26. Lander 8 never released in June and
%                   so was not redeployed - it has no deployment 3.
%
%   Each deployment has two sheets in the spreadsheet: a 'Landers ...' sheet
%   with one four-row block per lander (one row per hydrophone) and a
%   'Waypoints ...' sheet with the GPS waypoints taken on the day.
%
%   POSITIONS. Drop and retrieval positions are taken from the waypoint
%   sheet where it has them, because those are the ones actually logged on
%   the GPS and are what the analysis scripts use; the lander sheet's own
%   latitude/longitude columns are the fallback. The two disagree in places -
%   the Oct 24 sheet writes 12.52278 for lander 2 where the waypoint (and the
%   neighbouring landers) say 12.5338 - so preferring the waypoint matters.
%   Where a lander has more than one waypoint with the same name (landers 2-9
%   in Oct 24 each have two, seconds apart) the last one is taken.
%
%   The Feb 25 and June 25 lander sheets write longitude in the 'Latitude'
%   column and latitude in the 'Longitude' column. Rather than hard code
%   which sheet is which way round, positions are sorted by value: this site
%   is near 54.75 N, 12.54 E, so the value near 54 is the latitude. See
%   CUMBIAHLATLON below.
%
%   TIMES. STARTTIME is the deployment date plus the 'Time for deployment'
%   time of day, i.e. when the lander went over the side. ENDTIME is the
%   retrieval date, with a time of day only where the spreadsheet gives one.
%   SYNCTIME is the GPS clock synchronisation done on deck; the Oct 24 sheet
%   writes it as a ten second range ('06:22:30-06:22:40') and the start of
%   that range is used.
%
%   See also GETDANISHLANDERPATHS, GETDANISHLANDERDEPLOYMENTINFO,
%   CUMBIAHDATADEFAULTS.

persistent cached

if nargin > 0 && refresh
    cached = [];
end
if ~isempty(cached)
    T = cached;
    return;
end

posfile = cumbiahsettingsfile();

% deployment number -> the pair of sheets describing it
sheets = {
    1, 'Landers Oct 24',    'Waypoints Oct 24'
    2, 'Landers Feb 2025',  'Waypoints feb 2025'
    3, 'Landers June 2025', 'Waypoints June 2025'
    };

T = cumbiahdatadefaults();
T(:) = [];

for s = 1:size(sheets,1)
    deployment = sheets{s,1};
    rows = readdeploymentsheet(posfile, sheets{s,2}, deployment);
    [dropwpt, retrievewpt] = readwaypointsheet(posfile, sheets{s,3});

    for i = 1:numel(rows)
        r = rows(i);
        % waypoints win over the lander sheet's own columns - see above
        if isKey(dropwpt, r.landernumber)
            r.droplocation = dropwpt(r.landernumber);
        end
        if isKey(retrievewpt, r.landernumber)
            r.retrievelocation = retrievewpt(r.landernumber);
        end
        T(end+1) = r; %#ok<AGROW>
    end
end

cached = T;

end

% ------------------------------------------------------------------------
function f = cumbiahsettingsfile()
%CUMBIAHSETTINGSFILE Path to the lander settings spreadsheet.
%   The file name carries a date that changes as the spreadsheet is revised
%   ('Lander settings LKY_PBJ 2026-01-08.xlsx'), so match on the stem and
%   take the most recently modified. Excel lock files ('~$...') are skipped.

denmarkdir = getlandersuperfolder('Denmark');
d = dir(fullfile(denmarkdir, 'Lander settings*.xlsx'));
d = d(~startsWith({d.name}, '~$'));

if isempty(d)
    error('cumbiahlandertable:noSettingsFile', ...
        'No ''Lander settings*.xlsx'' found in %s.', denmarkdir);
end

[~, newest] = max([d.datenum]);
f = fullfile(d(newest).folder, d(newest).name);

end

% ------------------------------------------------------------------------
function rows = readdeploymentsheet(posfile, sheet, deployment)
%READDEPLOYMENTSHEET One 'Landers ...' sheet as a struct array.
%   One element per lander that was actually deployed. The sheet has one
%   four row block per lander: the first row carries the lander number and
%   everything about the deployment, the four rows carry one hydrophone
%   each. Blocks below the main table (the 'Time for setting up ...' summary
%   tables) repeat the lander numbers but have no deployment date, which is
%   how they are told apart from real deployments. The June 25 sheet has a
%   row for lander 8 with no dates at all - it never came up in June and so
%   was not redeployed - and that is skipped by the same test.

C = readcell(posfile, 'Sheet', sheet);
hdr = strtrim(string(cellfun(@(v) tostr(v), C(1,:), 'UniformOutput', false)));

% The header row repeats names - 'Latitude', 'Longitude' and 'Notes' all
% appear twice, once for deployment and once for retrieval - so columns are
% found by name plus which occurrence of it is wanted. The June 25 sheet has
% an extra 'Screenshot, UTC' column and a 'Time for start' column, so the
% column numbers differ between sheets and cannot be hard coded.
cLander  = findcol(hdr, 'Lander', 1);
cST      = findcol(hdr, 'Soundtrap ID', 1);
cHyd     = findcol(hdr, 'Hydrophone', 1);
cPos     = findcol(hdr, 'Position on SoundTrap', 1);
cColour  = findcol(hdr, 'Colour', 1);
cDuty    = findcol(hdr, 'Duty cycle', 1);
cRel     = findcol(hdr, 'Releaser', 1);
cCpod    = findcol(hdr, 'CPOD', 1);
cDate    = findcol(hdr, 'Date of deployment and synchronization', 1);
cSync    = findcol(hdr, 'Time for GPS synchronization on deck (UTC)', 1);
cDepTime = findcol(hdr, 'Time for deployment', 1);
cDepLat  = findcol(hdr, 'Latitude', 1);
cDepLon  = findcol(hdr, 'Longitude', 1);
cRetDate = findcol(hdr, 'Retrieval Date', 1);
cRetLat  = findcol(hdr, 'Latitude', 2);
cRetLon  = findcol(hdr, 'Longitude', 2);

rows = cumbiahdatadefaults();
rows(:) = [];

for r = 2:size(C,1)
    lander = tonum(getcell(C, r, cLander));
    depdate = todate(getcell(C, r, cDate));
    if isnan(lander) || isnat(depdate)
        continue;   % not the start of a real deployment block
    end

    d = cumbiahdatadefaults();
    d.landernumber = lander;
    d.deployment   = deployment;
    d.serialnumber = tonum(getcell(C, r, cST));
    d.dutycycle    = tonum(getcell(C, r, cDuty));
    d.releaser     = tonum(getcell(C, r, cRel));
    d.cpod         = tonum(getcell(C, r, cCpod));

    % ---- times
    % Excel stores a time of day as a fraction of a day, so the arithmetic
    % lands a millisecond or so off the whole second that was typed; round
    % it back. The display format is forced too, because a date column that
    % Excel formatted without a time gives a datetime that hides its time of
    % day - which makes a correct STARTTIME look like midnight.
    d.startTime = fixtime(depdate + totimeofday(getcell(C, r, cDepTime)));
    d.synctime  = fixtime(depdate + totimeofday(getcell(C, r, cSync)));
    % the retrieval cell is sometimes a bare date and sometimes a full
    % timestamp, so take it whole rather than splitting off a time of day
    d.endTime = fixtime(todatetime(getcell(C, r, cRetDate)));

    % ---- positions (overwritten later by the waypoints where they exist)
    d.droplocation     = cumbiahlatlon(tonum(getcell(C, r, cDepLat)), ...
                                       tonum(getcell(C, r, cDepLon)));
    d.retrievelocation = cumbiahlatlon(tonum(getcell(C, r, cRetLat)), ...
                                       tonum(getcell(C, r, cRetLon)));

    % ---- hydrophones: this row and the three below it, placed by the
    % 'Position on SoundTrap' column so that index == SoundTrap channel
    ids     = nan(4,1);
    colours = strings(4,1);
    for k = 0:3
        if r+k > size(C,1)
            break;
        end
        if k > 0 && ~isnan(tonum(getcell(C, r+k, cLander)))
            break;      % ran into the next lander's block
        end
        hyd = tonum(getcell(C, r+k, cHyd));
        pos = tonum(getcell(C, r+k, cPos));
        if isnan(hyd) || isnan(pos) || pos < 1 || pos > 4
            continue;
        end
        ids(pos)     = hyd;
        colours(pos) = strtrim(tostr(getcell(C, r+k, cColour)));
    end
    d.hydrophoneIDs     = ids;
    d.hydrophonecolours = colours;

    rows(end+1) = d; %#ok<AGROW>
end

end

% ------------------------------------------------------------------------
function [dropwpt, retrievewpt] = readwaypointsheet(posfile, sheet)
%READWAYPOINTSHEET Lander drop and retrieval waypoints from one sheet.
%   Returns two containers.Map keyed on lander number holding [lat lon].
%
%   Waypoint rows are identified by their 'Explanation' column rather than
%   by name, because the naming is inconsistent between trips ('LANDER1' with
%   a corrected name of 'LANDER1B' in Oct 24, 'LANDER8C' in Feb 25,
%   'LANDER1D' in June 25). Rows explained as 'Position of lander' are drops
%   and rows explained as 'Retrieval position of lander N' are recoveries.
%   The lander number comes from the explanation where it is written there,
%   otherwise from the waypoint name.
%
%   Note the deployment 1 recoveries are logged on the Oct 24 waypoint sheet
%   (as 'LAND2UP' and so on, taken 2025-03-29), which is why drops and
%   retrievals are read from the same sheet. Landers 1, 5, 7 and 8 were lifted
%   on 2025-02-02 with no retrieval waypoint, so they keep the lander sheet's
%   position. The release code waypoints ('LANDER2B REL') are the vessel
%   circling to talk to the releaser, not a lander position, and are ignored.

dropwpt     = containers.Map('KeyType', 'double', 'ValueType', 'any');
retrievewpt = containers.Map('KeyType', 'double', 'ValueType', 'any');

C = readcell(posfile, 'Sheet', sheet);
hdr = strtrim(string(cellfun(@(v) tostr(v), C(1,:), 'UniformOutput', false)));

cName    = findcol(hdr, 'name', 1);
cCorr    = findcol(hdr, 'Corrected name', 1);
cX       = findcol(hdr, 'xcoord', 1);
cY       = findcol(hdr, 'ycoord', 1);
cExplain = findcol(hdr, 'Explanation', 1);

for r = 2:size(C,1)
    explanation = strtrim(tostr(getcell(C, r, cExplain)));
    if strlength(explanation) == 0
        continue;
    end

    isdrop     = startsWith(explanation, 'Position of lander',           'IgnoreCase', true);
    isretrieve = startsWith(explanation, 'Retrieval position of lander', 'IgnoreCase', true);
    if ~isdrop && ~isretrieve
        continue;
    end

    lander = landerfromtext(explanation);
    if isnan(lander)
        lander = landerfromtext(tostr(getcell(C, r, cName)));
    end
    if isnan(lander)
        lander = landerfromtext(tostr(getcell(C, r, cCorr)));
    end
    if isnan(lander)
        continue;
    end

    % xcoord is longitude and ycoord latitude, but let CUMBIAHLATLON sort
    % them out by value so a swapped column cannot go unnoticed
    latlon = cumbiahlatlon(tonum(getcell(C, r, cY)), tonum(getcell(C, r, cX)));
    if isempty(latlon)
        continue;
    end

    % last waypoint wins - landers 2-9 in Oct 24 each have two, a couple of
    % seconds apart, and the later one is the settled position
    if isdrop
        dropwpt(lander) = latlon;
    else
        retrievewpt(lander) = latlon;
    end
end

end

% ------------------------------------------------------------------------
function n = landerfromtext(s)
%LANDERFROMTEXT Lander number out of a waypoint name or explanation.
%   Handles 'LANDER1', 'LANDER8C', 'LAND9UP', 'LANDER 2' and
%   'Retrieval position of lander 9'. Returns NaN if there is no number.

n = NaN;
s = tostr(s);
if strlength(s) == 0
    return;
end

tok = regexpi(char(s), 'LAND(?:ER)?\s*0*(\d+)', 'tokens', 'once');
if isempty(tok)
    return;
end
n = str2double(tok{1});

end

% ------------------------------------------------------------------------
function latlon = cumbiahlatlon(a, b)
%CUMBIAHLATLON A spreadsheet position as [lat lon], whichever way it was written.
%   The Denmark landers all sit within a few hundred metres of 54.75 N,
%   12.54 E, so latitude and longitude are told apart by value: latitude is
%   the one near 54 and longitude the one near 12. The Feb 25 and June 25
%   lander sheets have the two columns the wrong way round, and doing it by
%   value means a record read from either sheet, or from a waypoint row,
%   means the same thing. Longitude is EAST POSITIVE here, unlike the
%   CIBBRiNA gill net datasets.
%
%   Returns [] if either value is missing, and warns (once per session, the
%   table is cached) if the pair does not look like this site at all.

latlon = [];
if isnan(a) || isnan(b)
    return;
end

islat = @(v) v > 50 && v < 60;
islon = @(v) v > 5  && v < 20;

if islat(a) && islon(b)
    latlon = [a, b];
elseif islat(b) && islon(a)
    latlon = [b, a];
else
    warning('cumbiahlandertable:oddPosition', ...
        ['Position [%g %g] is not near the Danish lander site (54.75 N, ' ...
         '12.54 E); taking it as [lat lon] unchanged.'], a, b);
    latlon = [a, b];
end

end

% ------------------------------------------------------------------------
function d = fixtime(d)
%FIXTIME Round a spreadsheet datetime to the second and show its time of day.
%   Excel times are fractions of a day, so 03:40:33 comes back as
%   03:40:32.999; and a datetime read from a cell formatted as a bare date
%   carries a date only display format, which would hide the time of day
%   added to it. Neither changes the value by more than a millisecond, but
%   both make the times hard to read.

if isnat(d)
    return;
end
d = dateshift(d, 'start', 'second', 'nearest');
d.Format = 'dd-MMM-uuuu HH:mm:ss';

end

% ------------------------------------------------------------------------
function c = findcol(hdr, name, occurrence)
%FINDCOL Column index of the OCCURRENCE'th header called NAME.
%   The lander sheets repeat header names for the retrieval block, so the
%   occurrence matters: 'Latitude' 1 is the drop position and 'Latitude' 2
%   the retrieval position. Returns [] when the sheet has no such column, and
%   GETCELL then quietly returns missing for it.

c = find(strcmpi(hdr, name));
if numel(c) < occurrence
    c = [];
    return;
end
c = c(occurrence);

end

% ------------------------------------------------------------------------
function v = getcell(C, r, c)
%GETCELL One cell, tolerating a column that this sheet does not have.
if isempty(c) || c > size(C,2) || r > size(C,1)
    v = missing;
    return;
end
v = C{r,c};
end

% ------------------------------------------------------------------------
function s = tostr(v)
%TOSTR One cell as a string, empty where the cell holds nothing usable.
if ismissing(v)
    s = "";
elseif isstring(v) || ischar(v)
    s = string(v);
elseif isnumeric(v) && isscalar(v)
    s = string(v);
else
    s = "";
end
end

% ------------------------------------------------------------------------
function n = tonum(v)
%TONUM One cell as a double, NaN where the cell is empty or text.
%   Text is tried as a number too, because a column that is numeric for most
%   landers occasionally carries 'na' or a typed digit string.
n = NaN;
if ismissing(v)
    return;
end
if isnumeric(v) && isscalar(v)
    n = double(v);
elseif ischar(v) || isstring(v)
    n = str2double(v);
end
end

% ------------------------------------------------------------------------
function d = todate(v)
%TODATE One cell as a date at midnight, NaT where it is not a date.
d = todatetime(v);
if ~isnat(d)
    d = dateshift(d, 'start', 'day');
end
end

% ------------------------------------------------------------------------
function d = todatetime(v)
%TODATETIME One cell as a datetime, NaT where it is not one.
%   READCELL hands back datetimes for date formatted cells but Excel serial
%   numbers or text for cells that were typed rather than formatted, so
%   handle all three.

d = NaT;
if ismissing(v)
    return;
end

if isdatetime(v)
    d = v;
    return;
end
if isnumeric(v) && isscalar(v) && v > 1000
    % an Excel serial date; anything smaller is a time of day, not a date
    d = datetime(v, 'ConvertFrom', 'excel');
    return;
end
if ischar(v) || isstring(v)
    fmts = {'yyyy-MM-dd HH:mm:ss', 'yyyy-MM-dd', 'dd/MM/yyyy'};
    for f = 1:numel(fmts)
        try %#ok<TRYNC>
            d = datetime(v, 'InputFormat', fmts{f});
            return;
        end
    end
end

end

% ------------------------------------------------------------------------
function t = totimeofday(v)
%TOTIMEOFDAY One cell as a time of day, to add to a deployment date.
%   Time only cells come back from READCELL as a duration, or as a datetime
%   on Excel's 1899 epoch, or as a fraction of a day, depending on how the
%   cell was written. Text is also handled, because the Oct 24 GPS
%   synchronisation column writes a ten second range ('06:22:30-06:22:40') -
%   the first time in the string is taken - and because cells like 'na' or
%   'See notes' appear where the time was never recorded.
%
%   Returns a NaN duration if there is no time, so that adding it to a date
%   gives NaT rather than silently giving midnight.

t = duration(NaN, 0, 0);
if ismissing(v)
    return;
end

if isduration(v)
    t = v;
    return;
end
if isdatetime(v)
    t = timeofday(v);
    return;
end
if isnumeric(v) && isscalar(v)
    if v >= 0 && v < 1
        t = days(v);            % Excel fraction of a day
    elseif v > 1000
        t = timeofday(datetime(v, 'ConvertFrom', 'excel'));
    end
    return;
end
if ischar(v) || isstring(v)
    % hh:mm:ss first, then hh:mm - one pattern with an optional seconds group
    % does not work here, because MATLAB drops a trailing optional group from
    % the token list rather than returning it empty
    tok = regexp(char(v), '(\d{1,2}):(\d{2}):(\d{2})', 'tokens', 'once');
    if isempty(tok)
        tok = regexp(char(v), '(\d{1,2}):(\d{2})', 'tokens', 'once');
    end
    if isempty(tok)
        return;
    end
    if numel(tok) < 3
        tok{3} = '0';
    end
    t = duration(str2double(tok{1}), str2double(tok{2}), str2double(tok{3}));
end

end
