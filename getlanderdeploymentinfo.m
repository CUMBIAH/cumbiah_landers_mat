function [startTime, endTime, serialNumber, hydrophoneIDs] = ...
    getlanderdeploymentinfo(landernumber, deploymentnumber)
%GETLANDERDEPLOYMENTINFO Deployment times and device IDs for one CUMBIAH lander.
%
%   [STARTTIME, ENDTIME, SERIALNUMBER, HYDROPHONEIDS] =
%   GETLANDERDEPLOYMENTINFO(LANDERNUMBER, DEPLOYMENTNUMBER) returns the
%   times and the instruments for one deployment of one seabed lander.
%
%   LANDERNUMBER is the lander, 1 to 9. DEPLOYMENTNUMBER is which of the
%   three deployments of the array is wanted:
%
%       1  Oct 24    deployed 2024-10-05, all nine landers
%       2  Feb 25    deployed 2025-02-03, landers 1, 5, 7 and 8 only
%       3  June 25   deployed 2025-06-26, every lander except 8
%
%   STARTTIME and ENDTIME bracket the recording period as a half open
%   interval [STARTTIME, ENDTIME): STARTTIME is when the lander went over the
%   side and ENDTIME when it was recovered. This matches the windows used by
%   GETLANDERDATAPATHS, so a value TIME satisfies STARTTIME <= TIME < ENDTIME
%   exactly when GETLANDERDATAPATHS resolves to this deployment.
%
%   SERIALNUMBER is the ID of the SoundTrap 4c on that lander (e.g. 8690).
%   Each lander kept the same SoundTrap for all three deployments, so unlike
%   the CIBBRiNA trips the serial number identifies the lander rather than
%   the deployment - which is why GETLANDERDATAPATHS needs a time as well.
%
%   HYDROPHONEIDS is a 4x1 vector of hydrophone serials indexed by position
%   on the SoundTrap, i.e. HYDROPHONEIDS(2) is the hydrophone on channel 2.
%   The hydrophones stayed on their landers too, so this is normally the same
%   across deployments; it is read per deployment rather than assumed.
%
%   Not every lander was in every deployment: only 1, 5, 7 and 8 were
%   redeployed in Feb 25, and lander 8 never released in June 25 and so has
%   no deployment 3. Asking for a combination that never happened is an
%   error, which lists the deployments that lander does have.
%
%   Everything here is read from the lander settings spreadsheet rather than
%   held in this file - see CUMBIAHLANDERTABLE.
%
%   Example:
%       [t0, t1, sn] = getlanderdeploymentinfo(1, 2);   % lander 1, Feb 25
%       data = getlanderdatapaths(sn, t0);            % data.sqlitedB, ...
%
%   See also GETLANDERDATAPATHS, CUMBIAHLANDERTABLE.

narginchk(2, 2);
if ~isnumeric(landernumber) || ~isscalar(landernumber)
    error('getlanderdeploymentinfo:badLander', 'LANDERNUMBER must be a scalar, e.g. 1.');
end
if ~isnumeric(deploymentnumber) || ~isscalar(deploymentnumber)
    error('getlanderdeploymentinfo:badDeployment', ...
        'DEPLOYMENTNUMBER must be a scalar: 1 (Oct 24), 2 (Feb 25) or 3 (June 25).');
end

T = cumbiahlandertable();

idx = find([T.landernumber] == landernumber & [T.deployment] == deploymentnumber, 1);

if isempty(idx)
    % say what this lander does have rather than just that this is missing -
    % the gaps (no Feb 25 for most landers, no June 25 for lander 8) are real
    % and easily forgotten
    onthislander = unique([T([T.landernumber] == landernumber).deployment]);
    if isempty(onthislander)
        error('getlanderdeploymentinfo:unknownLander', ...
            'No lander %d in the settings spreadsheet. Landers present: %s.', ...
            landernumber, mat2str(unique([T.landernumber])));
    end
    error('getlanderdeploymentinfo:notDeployed', ...
        'Lander %d was not deployed in deployment %d. It has deployments: %s.', ...
        landernumber, deploymentnumber, mat2str(onthislander));
end

startTime     = T(idx).startTime;
endTime       = T(idx).endTime;
serialNumber  = T(idx).serialnumber;
hydrophoneIDs = T(idx).hydrophoneIDs;

end
