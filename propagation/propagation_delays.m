function f = propagation_delays(P)
%PROPAGATION_DELAYS Function predicting the time delays of hydrophone pairs.
%
%   F = PROPAGATION_DELAYS(P) returns a function handle
%
%       TAU = F(X, H1, H2)
%
%   giving the time delay (s) of each hydrophone pair for a source at X
%   ([x y z], m, z up from the sea surface). H1 and H2 are n x 3 positions
%   of the first and second hydrophone of each pair (same frame). The delay
%   follows the PAMGuard convention, positive if the sound reaches H1
%   first: TAU = time at H2 - time at H1.
%
%   P is a propagation struct:
%     - straight line (STRAIGHT_PROPAGATION, or any struct with only a
%       SOUNDSPEED): TAU = (|X - H2| - |X - H1|)/SOUNDSPEED
%     - ray traced (MAKE_PROPAGATION_TABLE): the hydrophones of a pair are
%       a few cm apart, so the delay is set by the direction the wavefront
%       arrives from. The table gives the elevation SLANT the click arrives
%       from at the horizontal range and depth of X from the pair; the
%       azimuth is that of the straight line (the profile does not change
%       with range). With U the unit vector towards that direction,
%       TAU = -U.(H2 - H1)/SOUNDSPEED, SOUNDSPEED being the sound speed at
%       the hydrophones. Closer than the first range of the table, where
%       the wavefront is not plane, the straight line is used.
%
%   The table is for hydrophones at depth P.HDEPTH. A pair at another depth
%   is looked up as if the source were the same height above it, so keep
%   the hydrophone depth of the table close to the landers'.
%
%   See also MAKE_PROPAGATION_TABLE, STRAIGHT_PROPAGATION,
%   SELECT_PROPAGATION, LOCALISEPORPOISES.

c = P.soundspeed;
if ~isfield(P, 'type') || ~strcmp(P.type, 'raytrace')
    f = @(x, h1, h2) straight(x, h1, h2, c);
    return
end
F = griddedInterpolant({P.ranges(:), P.depths(:)}, P.slant, 'linear', 'nearest');
rmin = P.ranges(1);
dlim = [P.depths(1), P.depths(end)];
hdepth = P.hdepth;
f = @(x, h1, h2) raytrace(x, h1, h2, c, F, rmin, dlim, hdepth);
end

function tau = straight(x, h1, h2, c)
x = x(:)';
tau = (vecnorm(x - h2, 2, 2) - vecnorm(x - h1, 2, 2))/c;
end

function tau = raytrace(x, h1, h2, c, F, rmin, dlim, hdepth)
x = x(:)';
m = (h1 + h2)/2;                      % middle of each pair
dx = x(1) - m(:,1);
dy = x(2) - m(:,2);
r = hypot(dx, dy);
% depth of the source in the table: the same height above the pair
zs = -x(3) + (hdepth + m(:,3));
zs = min(max(zs, dlim(1)), dlim(2));
el = F(r, zs);                        % elevation of arrival (deg, up)
ce = cosd(el);
u = [ce.*dx./r, ce.*dy./r, sind(el)];
tau = -sum(u.*(h2 - h1), 2)/c;
near = r < rmin;
if any(near)
    tau(near) = straight(x, h1(near,:), h2(near,:), c);
end
end
