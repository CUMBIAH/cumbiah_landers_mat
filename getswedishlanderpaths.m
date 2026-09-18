function data = getswedishlanderpaths(serialnumber, time) %#ok<INUSD>
%GETSWEDISHLANDERPATHS Provides links to the CUMBIAH Sweden lander data.
%
%   DATA = GETSWEDISHLANDERPATHS(SERIALNUMBER,TIME) - NOT IMPLEMENTED YET. It
%   always returns CUMBIAHDATADEFAULTS(), i.e. "not a Swedish SoundTrap", so
%   that GETLANDERPATHS moves on to the next country.
%
%   WHAT IT NEEDS TO DO. Follow GETDANISHLANDERPATHS, which is the working
%   example. Given the SoundTrap 4c ID SERIALNUMBER and a TIME (a datenum or
%   a datetime), find the Swedish deployment that SoundTrap was in at that
%   time and return one struct DATA with every field of CUMBIAHDATADEFAULTS
%   filled in:
%
%       landernumber       - lander number, as the Swedish team numbers them
%       deployment         - deployment number within Sweden
%       serialnumber       - the SoundTrap 4c ID
%       startTime          - datetime the lander went in the water
%       endTime            - datetime it was recovered; the deployment is the
%                            half open window [startTime, endTime)
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
%   Positions are decimal degrees, WGS84, [lat lon], longitude east
%   positive. Paths should be rooted on GETLANDERSUPERFOLDER('Sweden') so
%   they follow the Dropbox folder between machines.
%
%   If no Swedish deployment matches SERIALNUMBER at TIME, return
%   CUMBIAHDATADEFAULTS() - do NOT raise an error. GETLANDERPATHS tries
%   every country in turn and relies on an empty LANDERNUMBER to move on.
%
%   The deployment details (times, positions, hydrophones) are best read
%   from a settings spreadsheet in the Sweden folder, as CUMBIAHLANDERTABLE
%   does for Denmark, rather than written into the code.
%
%   See also GETLANDERPATHS, GETDANISHLANDERPATHS, GETSWEDISHLANDERDEPLOYMENTINFO,
%   CUMBIAHDATADEFAULTS.

% not implemented - no Swedish SoundTrap is known yet
data = cumbiahdatadefaults();

end
