function P = straight_propagation(time, soundspeed)
%STRAIGHT_PROPAGATION Propagation struct for straight line propagation.
%
%   P = STRAIGHT_PROPAGATION(TIME, SOUNDSPEED) is a propagation struct for
%   LOCALISEPORPOISES with a single sound speed (m/s) at TIME (datetime;
%   NaT if it applies at any time). Sound travels in straight lines, as it
%   did before propagation tables were added. It can sit in a list with
%   ray traced tables (MAKE_PROPAGATION_TABLE), e.g. for times of year with
%   a well mixed water column.
%
%   See also MAKE_PROPAGATION_TABLE, PROPAGATION_DELAYS, SELECT_PROPAGATION.

if nargin < 2
    error('straight_propagation:args', 'Give a time and a sound speed.');
end
if isnumeric(time)
    time = datetime(time, 'ConvertFrom', 'datenum');
end
P.type = 'straight';
P.time = time;
P.soundspeed = soundspeed;
end
