function P = make_propagation_table(castfile, varargin)
%MAKE_PROPAGATION_TABLE Ray traced lookup table of how a click reaches a
%seabed lander, from one CTD cast, for LOCALISEPORPOISES.
%
%   P = MAKE_PROPAGATION_TABLE(CASTFILE) reads a CastAway cast (.csv, see
%   READ_CASTAWAY), or takes a profile struct CASTFILE with fields depth (m),
%   c (m/s), time (datetime), file (a name), lat and lon, traces a dense fan of rays from the lander hydrophone
%   through its sound speed profile with ACTUP BELLHOP(M) and finds the
%   direct path eigenray from every point of a range x depth grid (see
%   SLANT_REFRACTION_BIAS). The profile does not change with range, so one
%   table serves every lander of an array at the same depth.
%
%   P is a propagation struct (see PROPAGATION_DELAYS) with fields
%       type       - 'raytrace'
%       time       - time of the cast (UTC, datetime)
%       soundspeed - sound speed at the hydrophones (m/s): the speed the
%                    time delays across a lander's array are made with
%       meanspeed  - mean sound speed over the water column (m/s)
%       hdepth     - hydrophone depth the table is for (m)
%       seabed     - depth of the seabed (m)
%       ranges     - horizontal range from the lander (m), 1 x nr
%       depths     - depth of the source (m), 1 x nd
%       slant      - nr x nd: elevation the click arrives from at the
%                    lander (deg, positive up)
%       tau        - nr x nd: travel time (s)
%       shadow     - nr x nd: true where no direct ray reaches; SLANT and TAU
%                    there are those of the nearest point which has one
%       z, c       - the profile (m, m/s)
%       source, lat, lon, created, method
%
%   Name-value options:
%       'hdepth' - hydrophone depth (m) [17, the depth of the Danish landers
%                  used by LOCALISEPORPOISES]
%       'seabed' - seabed depth (m) [hdepth + 0.5]
%       'ranges' - [0.25:0.25:20, 20.5:0.5:50, 51:1:200, 202:2:1600]: out
%                  to the boat calibration lines of LOCATEPLATFORM
%       'depths' - [0:0.25:seabed]
%       'angles' - ray fan (deg, + down) [-89:0.02:89]
%
%   Example:
%       P = make_propagation_table('CC2043006_20250912_092555.csv');
%       f = propagation_delays(P);   % f(x, h1, h2): delays of hydrophone pairs
%
%   See also MAKE_PROPAGATION_TABLES, STRAIGHT_PROPAGATION,
%   PROPAGATION_DELAYS, SELECT_PROPAGATION, LOCALISEPORPOISES.

p = inputParser;
p.addParameter('hdepth', 17);
p.addParameter('seabed', []);
p.addParameter('ranges', [0.25:0.25:20, 20.5:0.5:50, 51:1:200, 202:2:1600]);
p.addParameter('depths', []);
p.addParameter('angles', -89:0.02:89);
p.parse(varargin{:});
opt = p.Results;
if isempty(opt.seabed), opt.seabed = opt.hdepth + 0.5; end
if isempty(opt.depths), opt.depths = 0:0.25:opt.seabed; end

if isstruct(castfile)
    cast = castfile;
    cast.depth = cast.depth(:); cast.c = cast.c(:);
else
    cast = read_castaway(castfile);
end
% the profile on a 0.5 m grid to the seabed (see LOAD_SITE_SVPS)
dz = 0.5;
zg = unique([(0:dz:opt.seabed)'; opt.seabed]);
ok = isfinite(cast.c);
cg = interp1(cast.depth(ok), cast.c(ok), zg, 'linear');
cg(zg < min(cast.depth(ok))) = cast.c(find(ok, 1, 'first'));
cg(zg > max(cast.depth(ok))) = cast.c(find(ok, 1, 'last'));
% bin average rather than point sample, so cast noise does not make caustics
for i = 1:numel(zg)
    in = abs(cast.depth - zg(i)) <= dz/2 & ok;
    if any(in), cg(i) = mean(cast.c(in)); end
end
if max(cast.depth) < opt.seabed - 1
    warning('make_propagation_table:shallowCast', ...
        '%s only reaches %.1f m; the profile is held constant below that.', cast.file, max(cast.depth));
end

B = slant_refraction_bias(zg, cg, opt.hdepth, opt.ranges, opt.depths, ...
    'angles', opt.angles, 'paths', 'D');

slant = B.D.slant;
tau = B.D.tau;
shadow = isnan(slant);
% where no direct ray arrives (a refraction shadow, or between the
% hydrophone and the seabed) use the nearest point which has one: the
% limiting ray, which is where diffracted energy comes from
if any(shadow(:))
    % along range first: a shadow beyond the last ray at a depth takes
    % that ray's angle; then along depth for anything left
    slant = fillmissing(fillmissing(slant, 'nearest', 1), 'nearest', 2);
    tau = fillmissing(fillmissing(tau, 'nearest', 1), 'nearest', 2);
    % travel time of a shadow point: at least the straight line time
    st = hypot(opt.ranges(:), opt.depths - opt.hdepth)/interp1(zg, cg, opt.hdepth);
    tau(shadow) = max(tau(shadow), st(shadow));
end

P.type = 'raytrace';
P.time = cast.time;
P.soundspeed = interp1(zg, cg, opt.hdepth);
P.meanspeed = mean(cg);
P.hdepth = opt.hdepth;
P.seabed = opt.seabed;
P.ranges = opt.ranges(:)';
P.depths = opt.depths(:)';
P.slant = slant;
P.tau = tau;
P.shadow = shadow;
P.z = zg;
P.c = cg;
P.source = cast.file;
P.lat = cast.lat;
P.lon = cast.lon;
P.created = datetime('now');
P.method = 'ACTUP v2.2L BELLHOP(M) ray trace, direct path eigenrays';
end
