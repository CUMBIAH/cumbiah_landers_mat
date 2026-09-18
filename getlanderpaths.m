function data = getlanderpaths(serialnumber, time)
%GETLANDERPATHS Data paths for any CUMBIAH lander, whichever country it is in.
%
%   DATA = GETLANDERPATHS(SERIALNUMBER,TIME) returns the deployment record
%   for the lander carrying the SoundTrap 4c with ID SERIALNUMBER at time
%   TIME (a datenum or a datetime). DATA has the fields listed in
%   CUMBIAHDATADEFAULTS: the lander and deployment numbers, the times, the
%   drop and retrieval positions, the hydrophones, and the paths to the
%   PAMGuard database, binary store and vessel GPS track.
%
%   Each country keeps its landers in its own folder, with its own settings
%   spreadsheet and its own get*landerpaths function that knows how to read
%   them. SoundTrap serial numbers are unique across the whole project, so
%   the country does not have to be given: each country's function is tried
%   in turn, and the first one that recognises SERIALNUMBER at TIME wins.
%   The countries are listed in COUNTRYFUNCS below:
%
%       Denmark   GETDANISHLANDERPATHS
%       Germany   GETGERMANLANDERPATHS   (not implemented yet)
%       Sweden    GETSWEDISHLANDERPATHS  (not implemented yet)
%
%   To add a country, write its get*landerpaths function with the same
%   inputs and outputs as GETDANISHLANDERPATHS and add a handle to it to
%   COUNTRYFUNCS. The one rule it must follow is that a SoundTrap it does
%   not know returns CUMBIAHDATADEFAULTS() - an empty LANDERNUMBER - rather
%   than an error, because that is how this function moves on to the next
%   country.
%
%   If no country knows the SoundTrap, a fully populated struct of neutral
%   defaults is returned (see CUMBIAHDATADEFAULTS). Check
%   ISEMPTY(DATA.LANDERNUMBER) to detect that.
%
%   Lander and deployment numbers are only unique within a country: German
%   lander 1 is not Danish lander 1. The serial number is what identifies a
%   lander across the project.
%
%   Example:
%       [t0, ~, sn] = getlanderdeploymentinfo(1, 1, 'Denmark');
%       data = getlanderpaths(sn, t0);
%
%   See also GETLANDERDEPLOYMENTINFO, GETDANISHLANDERPATHS,
%   GETGERMANLANDERPATHS, GETSWEDISHLANDERPATHS, CUMBIAHDATADEFAULTS.

countryfuncs = {
    @getdanishlanderpaths
    @getgermanlanderpaths
    @getswedishlanderpaths
    };

for i = 1:numel(countryfuncs)
    data = countryfuncs{i}(serialnumber, time);
    if ~isempty(data.landernumber)
        return;
    end
end

% no country knows this SoundTrap at this time
data = cumbiahdatadefaults();

end
