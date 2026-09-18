function [startTime, endTime, serialNumber, hydrophoneIDs] = ...
    getlanderdeploymentinfo(landernumber, deploymentnumber, country)
%GETLANDERDEPLOYMENTINFO Deployment times and device IDs for one CUMBIAH lander.
%
%   [STARTTIME, ENDTIME, SERIALNUMBER, HYDROPHONEIDS] =
%   GETLANDERDEPLOYMENTINFO(LANDERNUMBER, DEPLOYMENTNUMBER, COUNTRY) returns
%   the times and the instruments for one deployment of one seabed lander in
%   COUNTRY, one of 'Denmark', 'Germany' or 'Sweden' (case insensitive).
%
%   COUNTRY is needed because lander and deployment numbers are only unique
%   within a country - German lander 1 is not Danish lander 1. Each country
%   has its own function that does the work:
%
%       Denmark   GETDANISHLANDERDEPLOYMENTINFO
%       Germany   GETGERMANLANDERDEPLOYMENTINFO   (not implemented yet)
%       Sweden    GETSWEDISHLANDERDEPLOYMENTINFO  (not implemented yet)
%
%   STARTTIME and ENDTIME bracket the recording period as a half open
%   interval [STARTTIME, ENDTIME): STARTTIME is when the lander went over the
%   side and ENDTIME when it was recovered. SERIALNUMBER is the ID of the
%   SoundTrap 4c on that lander (e.g. 8690), and is unique across the whole
%   project, so STARTTIME and SERIALNUMBER can be passed straight to
%   GETLANDERPATHS without saying the country again. HYDROPHONEIDS is a 4x1
%   vector of hydrophone serials indexed by channel.
%
%   To add a country, write its get*landerdeploymentinfo function with the
%   same inputs and outputs as GETDANISHLANDERDEPLOYMENTINFO and add a case
%   for it below.
%
%   Example:
%       [t0, t1, sn] = getlanderdeploymentinfo(1, 2, 'Denmark');   % Feb 25
%       data = getlanderpaths(sn, t0);                           % data.sqlitedB, ...
%
%   See also GETLANDERPATHS, GETDANISHLANDERDEPLOYMENTINFO,
%   GETGERMANLANDERDEPLOYMENTINFO, GETSWEDISHLANDERDEPLOYMENTINFO.

narginchk(3, 3);
if ~(ischar(country) || (isstring(country) && isscalar(country)))
    error('getlanderdeploymentinfo:badCountry', ...
        'COUNTRY must be ''Denmark'', ''Germany'' or ''Sweden''.');
end

switch lower(char(country))

    case 'denmark'
        [startTime, endTime, serialNumber, hydrophoneIDs] = ...
            getdanishlanderdeploymentinfo(landernumber, deploymentnumber);

    case 'germany'
        [startTime, endTime, serialNumber, hydrophoneIDs] = ...
            getgermanlanderdeploymentinfo(landernumber, deploymentnumber);

    case 'sweden'
        [startTime, endTime, serialNumber, hydrophoneIDs] = ...
            getswedishlanderdeploymentinfo(landernumber, deploymentnumber);

    otherwise
        error('getlanderdeploymentinfo:unknownCountry', ...
            'Unknown country ''%s''. Known countries: Denmark, Germany, Sweden.', ...
            char(country));

end

end
