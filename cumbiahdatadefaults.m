function data = cumbiahdatadefaults()
%CUMBIAHDATADEFAULTS Empty lander record for the CUMBIAH lander functions.
%
%   DATA = CUMBIAHDATADEFAULTS() returns a struct with every field of a
%   CUMBIAH lander deployment record set to a neutral default, so that
%   GETLANDERDATAPATHS always hands back a fully populated struct whether or not
%   it found a deployment.
%
%   Positions are decimal degrees, WGS84, latitude north positive and
%   longitude EAST positive - the CUMBIAH landers are in the Danish Great
%   Belt (~54.75 N, 12.54 E), so unlike the CIBBRiNA gill net datasets
%   longitude here is positive. Positions are always [lat lon] in that
%   order, whichever way round the spreadsheet happened to write them.
%
%   See also GETLANDERDATAPATHS, GETLANDERDEPLOYMENTINFO, CUMBIAHLANDERTABLE.

% ---- what and when -----------------------------------------------------
data.landernumber        = [];    % 1-9
data.deployment          = [];    % 1 = Oct 24, 2 = Feb 25, 3 = June 25
data.serialnumber        = [];    % SoundTrap 4c ID (e.g. 8690)
data.startTime           = NaT;   % went in the water
data.endTime             = NaT;   % came back out
data.synctime            = NaT;   % GPS clock synchronisation on deck

% ---- where -------------------------------------------------------------
data.droplocation        = [];    % [lat lon] where the lander was dropped
data.retrievelocation    = [];    % [lat lon] where it was picked up

% ---- the instrument ----------------------------------------------------
% hydrophoneIDs and hydrophonecolours are 4x1, indexed by position on the
% SoundTrap, i.e. hydrophoneIDs(2) is the hydrophone on channel 2.
data.hydrophoneIDs       = [];
data.hydrophonecolours   = strings(0,1);
data.dutycycle           = NaN;
data.releaser            = [];
data.cpod                = [];

% ---- data paths --------------------------------------------------------
% One database and one binary store per lander, holding every deployment -
% see GETLANDERDATAPATHS for the folder layout.
data.sqlitedB            = '';    % annotated database (the analysis one)
data.rawsqlitedB         = '';    % database as written by PAMGuard
data.binaryfolder        = '';    % PAMBinary (clicks etc.)
data.sensorbinaryfolder  = '';    % PAMBinary_sud_sensor (SoundTrap sensors)
data.psfxfile            = '';    % PAMGuard configuration
data.gpsfile             = '';    % vessel GPS track for this deployment trip

end
