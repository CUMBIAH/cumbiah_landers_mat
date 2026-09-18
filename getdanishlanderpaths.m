function data = getdanishlanderpaths(serialnumber, time)
%GETDANISHLANDERPATHS Provides links to 4 channel soundtrap lander data for
%the CUMBIAH Denmark landers
%
%   DATA = GETDANISHLANDERPATHS(SERIALNUMBER,TIME) returns a struct DATA
%   describing the CUMBIAH Denmark seabed lander carrying the SoundTrap 4c with ID
%   SERIALNUMBER (e.g. 8690) at time TIME. TIME may be a datenum or a
%   datetime. The struct has the following fields:
%
%       landernumber       - lander this SoundTrap was on (1-9)
%       deployment         - 1 (Oct 24), 2 (Feb 25) or 3 (June 25)
%       serialnumber       - the SoundTrap 4c ID
%       startTime          - datetime the lander went in the water
%       endTime            - datetime it was recovered
%       synctime           - datetime of the GPS clock sync on deck
%       droplocation       - [lat lon] where the lander was dropped
%       retrievelocation   - [lat lon] where it was picked up
%       hydrophoneIDs      - 4x1 hydrophone serials, indexed by channel
%       hydrophonecolours  - 4x1 hydrophone colours, indexed by channel
%       dutycycle          - recording duty cycle
%       releaser           - acoustic releaser code
%       cpod               - CPOD serial on the lander
%       sqlitedB           - annotated PAMGuard database (the analysis one)
%       rawsqlitedB        - database as written by PAMGuard
%       binaryfolder       - PAMGuard binary store (clicks etc.)
%       sensorbinaryfolder - binary store of the SoundTrap sensor data
%       psfxfile           - PAMGuard configuration
%       gpsfile            - vessel GPS track for this deployment trip
%
%   The landers sat on the seabed in the Danish Great Belt, so unlike the
%   CIBBRiNA gill net data there is no net position and no drift - one lander
%   has one position per deployment. Positions are decimal degrees, WGS84,
%   latitude north positive and longitude EAST POSITIVE.
%
%   DATA IS ORGANISED BY LANDER, NOT BY DEPLOYMENT. Each lander folder holds
%   the whole time series for that lander, all three deployments in one
%   database and one binary store:
%
%       lander<N>/
%           lander<N>_Denmark_database_annotated.sqlite3   <- sqlitedB
%           pamguard/
%               lander<N>_Denmark_database.sqlite3         <- rawsqlitedB
%               Lander<N>_Denmark.psfx                     <- psfxfile
%               PAMBinary/                                 <- binaryfolder
%               PAMBinary_sud_sensor/                      <- sensorbinaryfolder
%
%   So SQLITEDB and BINARYFOLDER are the same for every deployment of a given
%   lander, and it is DROPLOCATION, RETRIEVELOCATION and the times that change
%   with TIME. Use STARTTIME and ENDTIME to slice the shared store down to the
%   requested deployment.
%
%   The layout above is the convention, not a rule the code applies: every
%   path is written out per lander in CUMBIAHADDPATHS below, rooted on
%   GETLANDERSUPERFOLDER so that the whole set follows the Dropbox folder
%   between machines. Lander 2 already departs from the convention in two
%   ways, so hard coding the paths keeps that readable and gives one obvious
%   place to edit when a folder is renamed or a new lander is processed.
%   Nothing checks that a path exists, so a lander that has not been
%   processed yet returns the path its data will have.
%
%   The deployment itself, the positions and the hydrophone IDs come from the
%   lander settings spreadsheet in the Denmark folder rather than from this
%   code - see CUMBIAHLANDERTABLE for how that is read and for which landers
%   were deployed when. SERIALNUMBER alone is not enough to identify a
%   deployment, because a lander kept the same SoundTrap across all three; it
%   is TIME that picks the deployment.
%
%   If no deployment matches, a fully populated struct of neutral defaults is
%   returned (see CUMBIAHDATADEFAULTS) so callers do not have to special case
%   it. Check ISEMPTY(DATA.LANDERNUMBER) to detect that. GETLANDERPATHS
%   relies on this: it tries each country's function in turn and takes the
%   first that finds the SoundTrap, so use GETLANDERPATHS rather than
%   calling this directly unless you know the lander is Danish.
%
%   Example:
%       [t0, ~, sn] = getlanderdeploymentinfo(1, 1, 'Denmark');   % lander 1, Oct 24
%       data = getdanishlanderpaths(sn, t0);
%       clicks = import_clk_train(data.sqlitedB, data.binaryfolder, ...
%           'eventtype', 'bc');
%
%   See also GETLANDERPATHS, GETDANISHLANDERDEPLOYMENTINFO, CUMBIAHLANDERTABLE,
%   CUMBIAHDATADEFAULTS.

% Ensure time is a datetime (accept datenum or datetime)
time = cumbiahdatetime(time);

T = cumbiahlandertable();

% ---- Find the deployment -----------------------------------------------
% A lander keeps its SoundTrap for the whole project, so the serial number
% picks the lander and TIME picks which of its deployments. The windows
% cannot overlap: a lander is either in the water or on the boat.
data = [];
for i = 1:numel(T)
    if T(i).serialnumber ~= serialnumber
        continue;
    end
    if time >= T(i).startTime && time < T(i).endTime
        data = T(i);
        break;
    end
end

if isempty(data)
    % no lander deployment covers this SoundTrap at this time, but still
    % return a fully populated struct
    data = cumbiahdatadefaults();
    return;
end

% ---- Data paths --------------------------------------------------------
data = cumbiahaddpaths(data);

end

% ------------------------------------------------------------------------
function data = cumbiahaddpaths(data)
%CUMBIAHADDPATHS Fill in the file and folder paths for this lander.
%   The paths depend on the lander number alone, because one lander folder
%   holds every deployment of that lander - it is the positions and the times
%   that change with the deployment.
%
%   Every path is written out per lander rather than built from a pattern.
%   The folders are not consistent enough for a pattern to be honest about:
%   lander 2's sensor store is
%   'PAMBinary_sensor' where lander 3's is 'PAMBinary_sud_sensor', and its
%   annotated database sits inside that folder rather than at the lander root
%   as lander 1's does. Spelling them out is shorter than describing the
%   exceptions, and it puts the one obvious place to make a change when a
%   folder is renamed, moved, or added.
%
%   Only the root comes from elsewhere, via GETLANDERSUPERFOLDER, so the
%   whole set follows the main folder between machines.

d = getlandersuperfolder('Denmark');

switch data.landernumber

    case 1
        data.sqlitedB           = fullfile(d, 'lander1', 'lander1_Denmark_database_annotated.sqlite3');
        data.rawsqlitedB        = fullfile(d, 'lander1', 'pamguard', 'lander1_Denmark_database.sqlite3');
        data.psfxfile           = fullfile(d, 'lander1', 'pamguard', 'Lander1_Denmark.psfx');
        data.binaryfolder       = fullfile(d, 'lander1', 'pamguard', 'PAMBinary');
        data.sensorbinaryfolder = fullfile(d, 'lander1', 'pamguard', 'PAMBinary_sud_sensor');

    case 2
        data.sqlitedB           = fullfile(d, 'lander2', 'pamguard', 'lander2_Denmark_database_annotated.sqlite3');
        data.rawsqlitedB        = fullfile(d, 'lander2', 'pamguard', 'lander2_Denmark_database.sqlite3');
        data.psfxfile           = fullfile(d, 'lander2', 'pamguard', 'Lander2_Denmark.psfx');
        data.binaryfolder       = fullfile(d, 'lander2', 'pamguard', 'PAMBinary');
        data.sensorbinaryfolder = fullfile(d, 'lander2', 'pamguard', 'PAMBinary_sensor');

    case 3
        data.sqlitedB           = fullfile(d, 'lander3', 'pamguard', 'lander3_Denmark_database_annotated.sqlite3');
        data.rawsqlitedB        = fullfile(d, 'lander3', 'pamguard', 'lander3_Denmark_database.sqlite3');
        data.psfxfile           = fullfile(d, 'lander3', 'pamguard', 'Lander3_Denmark.psfx');
        data.binaryfolder       = fullfile(d, 'lander3', 'pamguard', 'PAMBinary');
        data.sensorbinaryfolder = fullfile(d, 'lander3', 'pamguard', 'PAMBinary_sud_sensor');

    case 4
        data.sqlitedB           = fullfile(d, 'lander4', 'lander4_Denmark_database_annotated.sqlite3');
        data.rawsqlitedB        = fullfile(d, 'lander4', 'pamguard', 'lander4_Denmark_database.sqlite3');
        data.psfxfile           = fullfile(d, 'lander4', 'pamguard', 'Lander4_Denmark.psfx');
        data.binaryfolder       = fullfile(d, 'lander4', 'pamguard', 'PAMBinary');
        data.sensorbinaryfolder = fullfile(d, 'lander4', 'pamguard', 'PAMBinary_sud_sensor');

    case 5
        data.sqlitedB           = fullfile(d, 'lander5', 'lander5_Denmark_database_annotated.sqlite3');
        data.rawsqlitedB        = fullfile(d, 'lander5', 'pamguard', 'lander5_Denmark_database.sqlite3');
        data.psfxfile           = fullfile(d, 'lander5', 'pamguard', 'Lander5_Denmark.psfx');
        data.binaryfolder       = fullfile(d, 'lander5', 'pamguard', 'PAMBinary');
        data.sensorbinaryfolder = fullfile(d, 'lander5', 'pamguard', 'PAMBinary_sud_sensor');

    case 6
        data.sqlitedB           = fullfile(d, 'lander6', 'lander6_Denmark_database_annotated.sqlite3');
        data.rawsqlitedB        = fullfile(d, 'lander6', 'pamguard', 'lander6_Denmark_database.sqlite3');
        data.psfxfile           = fullfile(d, 'lander6', 'pamguard', 'Lander6_Denmark.psfx');
        data.binaryfolder       = fullfile(d, 'lander6', 'pamguard', 'PAMBinary');
        data.sensorbinaryfolder = fullfile(d, 'lander6', 'pamguard', 'PAMBinary_sud_sensor');

    case 7
        data.sqlitedB           = fullfile(d, 'lander7', 'lander7_Denmark_database_annotated.sqlite3');
        data.rawsqlitedB        = fullfile(d, 'lander7', 'pamguard', 'lander7_Denmark_database.sqlite3');
        data.psfxfile           = fullfile(d, 'lander7', 'pamguard', 'Lander7_Denmark.psfx');
        data.binaryfolder       = fullfile(d, 'lander7', 'pamguard', 'PAMBinary');
        data.sensorbinaryfolder = fullfile(d, 'lander7', 'pamguard', 'PAMBinary_sud_sensor');

    case 8
        data.sqlitedB           = fullfile(d, 'lander8', 'lander8_Denmark_database_annotated.sqlite3');
        data.rawsqlitedB        = fullfile(d, 'lander8', 'pamguard', 'lander8_Denmark_database.sqlite3');
        data.psfxfile           = fullfile(d, 'lander8', 'pamguard', 'Lander8_Denmark.psfx');
        data.binaryfolder       = fullfile(d, 'lander8', 'pamguard', 'PAMBinary');
        data.sensorbinaryfolder = fullfile(d, 'lander8', 'pamguard', 'PAMBinary_sud_sensor');

    case 9
        data.sqlitedB           = fullfile(d, 'lander9', 'lander9_Denmark_database_annotated.sqlite3');
        data.rawsqlitedB        = fullfile(d, 'lander9', 'pamguard', 'lander9_Denmark_database.sqlite3');
        data.psfxfile           = fullfile(d, 'lander9', 'pamguard', 'Lander9_Denmark.psfx');
        data.binaryfolder       = fullfile(d, 'lander9', 'pamguard', 'PAMBinary');
        data.sensorbinaryfolder = fullfile(d, 'lander9', 'pamguard', 'PAMBinary_sud_sensor');

    otherwise
        error('getdanishlanderpaths:unknownLander', ...
            'No paths defined for lander %d. Landers 1 to 9 are known.', ...
            data.landernumber);

end

% one GPS track per deployment trip, shared by every lander on it
data.gpsfile = fullfile(d, 'GPS', ...
    sprintf('denmark_deployment%d_gps.mat', data.deployment));

end

% ------------------------------------------------------------------------
function time = cumbiahdatetime(time)
%CUMBIAHDATETIME Normalise a query time to a datetime.
%   Accepts either a datenum or a datetime, so that callers can pass whatever
%   they already have, and always returns a datetime to compare against the
%   spreadsheet's deployment windows.

if isnumeric(time)
    time = datetime(time, 'ConvertFrom', 'datenum');
elseif ~isdatetime(time)
    error('getdanishlanderpaths:badTime', 'TIME must be a datenum or datetime scalar.');
end

end
