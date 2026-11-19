function [P, k] = select_propagation(props, t, match)
%SELECT_PROPAGATION The propagation struct closest in time.
%
%   [P, K] = SELECT_PROPAGATION(PROPS, T) returns the propagation struct of
%   PROPS (a struct, a struct array or a cell array of structs, see
%   MAKE_PROPAGATION_TABLE and STRAIGHT_PROPAGATION) whose TIME is closest
%   to T (datetime or datenum), and its index K. A struct with no time (or
%   NaT) is only chosen if no struct has a time.
%
%   Times are compared by full date, not by time of year: a cast from
%   another year is far away in time, so give casts from the deployment
%   when there are some.
%
%   SELECT_PROPAGATION(PROPS, T, 'season') compares the time of year
%   instead, ignoring the year (the day of the year, wrapping round from
%   December to January), for when there is no cast from the deployment
%   and the sound speed profile is taken to change with the season.
%   SELECT_PROPAGATION(PROPS, T, 'time') is the default.
%
%   See also LOCALISEPORPOISES, PROPAGATION_DELAYS.

if isstruct(props)
    props = num2cell(props);
end
if isempty(props)
    error('select_propagation:empty', 'No propagation structs given.');
end
if isnumeric(t)
    t = datetime(t, 'ConvertFrom', 'datenum');
end
if nargin < 3 || isempty(match)
    match = 'time';
end
match = validatestring(match, {'time', 'season'});
n = numel(props);
dt = inf(n, 1);
for i = 1:n
    check_propagation(props{i});
    if isfield(props{i}, 'time') && ~isempty(props{i}.time) && ~isnat(props{i}.time)
        ti = props{i}.time;
        ti.TimeZone = ''; tt = t; tt.TimeZone = '';
        if strcmp(match, 'season')
            % days apart in the year, whichever the year
            d = mod(day(ti, 'dayofyear') + timeofday(ti)/days(1) - ...
                (day(tt, 'dayofyear') + timeofday(tt)/days(1)), 365.25);
            dt(i) = min(d, 365.25 - d);
        else
            dt(i) = abs(days(ti - tt));
        end
    end
end
if all(isinf(dt))
    k = 1;
else
    [~, k] = min(dt);
end
P = props{k};
end

function check_propagation(P)
if ~isfield(P, 'soundspeed') || ~isscalar(P.soundspeed) || ~isfinite(P.soundspeed)
    error('select_propagation:badStruct', 'A propagation struct needs a scalar SOUNDSPEED (m/s).');
end
if isfield(P, 'type') && strcmp(P.type, 'raytrace') && ~all(isfield(P, {'ranges', 'depths', 'slant', 'hdepth'}))
    error('select_propagation:badStruct', 'A ray trace propagation struct needs ranges, depths, slant and hdepth.');
end
end
