function [startTime, endTime, serialNumber, hydrophoneIDs] = ...
    getswedishlanderdeploymentinfo(landernumber, deploymentnumber) %#ok<STOUT,INUSD>
%GETSWEDISHLANDERDEPLOYMENTINFO Deployment times and device IDs for one CUMBIAH
%Sweden lander.
%
%   [STARTTIME, ENDTIME, SERIALNUMBER, HYDROPHONEIDS] =
%   GETSWEDISHLANDERDEPLOYMENTINFO(LANDERNUMBER, DEPLOYMENTNUMBER) - NOT
%   IMPLEMENTED YET. It raises an error.
%
%   WHAT IT NEEDS TO RETURN. Follow GETDANISHLANDERDEPLOYMENTINFO, which is
%   the working example. For Swedish lander LANDERNUMBER in Swedish
%   deployment DEPLOYMENTNUMBER (both numbered as the Swedish team numbers
%   them):
%
%       STARTTIME     - datetime the lander went over the side
%       ENDTIME       - datetime it was recovered. [STARTTIME, ENDTIME) must
%                       be the same half open window GETSWEDISHLANDERPATHS
%                       uses, so that GETLANDERPATHS(SERIALNUMBER, STARTTIME)
%                       resolves to this deployment.
%       SERIALNUMBER  - ID of the SoundTrap 4c on the lander (e.g. 8690)
%       HYDROPHONEIDS - 4x1 hydrophone serials, indexed by channel, i.e.
%                       HYDROPHONEIDS(2) is the hydrophone on channel 2
%
%   If the lander was not in that deployment, raise an error that lists the
%   deployments the lander does have, as the Danish function does.
%
%   The details are best read from the same settings spreadsheet that
%   GETSWEDISHLANDERPATHS reads, so the two can never disagree.
%
%   See also GETLANDERDEPLOYMENTINFO, GETDANISHLANDERDEPLOYMENTINFO,
%   GETSWEDISHLANDERPATHS.

error('getswedishlanderdeploymentinfo:notImplemented', ...
    'Swedish landers are not implemented yet - see GETSWEDISHLANDERDEPLOYMENTINFO.');

end
