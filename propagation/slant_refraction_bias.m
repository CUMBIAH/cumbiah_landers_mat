function B = slant_refraction_bias(z, c, hdepth, ranges, depths, varargin)
%SLANT_REFRACTION_BIAS Received slant angle at a seabed lander through a
%real sound speed profile, compared with the straight line slant.
%
%   B = SLANT_REFRACTION_BIAS(Z, C, HDEPTH, RANGES, DEPTHS) traces a dense
%   fan of rays from the lander hydrophone at HDEPTH (m) with ACTUP
%   BELLHOP(M) (see ACTUP_TRACE_RAYS) through the profile C(Z) and, by
%   reciprocity, finds the eigenrays from porpoises at every horizontal
%   range in RANGES (m) and depth in DEPTHS (m). Three paths are found:
%
%       'D' direct, 'S' one surface reflection, 'B' one seabed reflection
%
%   B is a struct with
%       ranges, depths, hdepth, seabed, z, c
%       ray      - the traced rays (struct array from ACTUP_TRACE_RAYS)
%       D, S, B  - one struct per path, each with nr x nd arrays
%           slant     - slant angle the click arrives from at the lander
%                       (deg, positive UP, NaN where there is no such ray:
%                       a refraction shadow)
%           geom      - the straight line (image source for S and B) slant
%                       a constant sound speed would give (deg)
%           bias      - slant - geom (deg)
%           tau       - travel time along the ray (s)
%           depthest  - depth a straight line localiser would put the
%                       click at, knowing the horizontal range exactly:
%                       HDEPTH - range*tand(slant) (m, for 'D')
%           deptherr  - depthest - true depth (m, + is deeper)
%           neig      - number of eigenrays found (more than 1 is a caustic;
%                       the one closest to the straight line is kept)
%
%   Name-value options:
%       'angles'   - launch angles traced (deg) [-80:0.02:80]
%       'paths'    - which paths to find, any of 'DSB' ['DSB']
%       other options are passed to ACTUP_TRACE_RAYS
%
%   See also ACTUP_TRACE_RAYS, RUN_REFRACTION_ANALYSIS.

p = inputParser;
p.KeepUnmatched = true;
p.addParameter('angles', -80:0.02:80);
p.addParameter('paths', 'DSB');
p.parse(varargin{:});
pass = namedargs2cell(p.Unmatched);

ranges = ranges(:)'; depths = depths(:)';
D = z(end);
paths = p.Results.paths;
rays = actup_trace_rays(z, c, hdepth, p.Results.angles, 'maxrange', max(ranges) + 5, ...
    'directonly', isequal(paths, 'D'), pass{:});
ang = [rays.angle]';
na = numel(ang); nr = numel(ranges); nd = numel(depths);

B.ranges = ranges; B.depths = depths; B.hdepth = hdepth; B.seabed = D;
B.z = z; B.c = c; B.ray = rays;

for ip = 1:numel(paths)
    pth = paths(ip);
    % depth and time of every ray at every range, on this path's leg
    Zr = nan(na, nr); Tr = nan(na, nr);
    for k = 1:na
        r = rays(k);
        switch pth
            case 'D', leg = r.nbnc == 0;
            otherwise
                if isempty(r.bnc) || r.bnc(1) ~= pth, continue; end
                leg = r.nbnc == 1;
        end
        % include the reflection point at the start of a reflected leg
        i = find(leg);
        if isempty(i), continue; end
        if pth ~= 'D' && i(1) > 1, i = [i(1)-1; i]; end
        rr = r.r(i); [rr, u] = unique(rr); zz = r.z(i(u)); tt = r.tau(i(u));
        if numel(rr) < 2, continue; end
        in = ranges >= rr(1) & ranges <= rr(end);
        Zr(k, in) = interp1(rr, zz, ranges(in));
        Tr(k, in) = interp1(rr, tt, ranges(in));
    end
    % eigenrays: where adjacent rays bracket the target depth
    S = nan(nr, nd); T = S; N = zeros(nr, nd);
    G = geomslant(pth, ranges', depths, hdepth, D);
    for ir = 1:nr
        zc = Zr(:, ir); tc = Tr(:, ir);
        for id = 1:nd
            d = zc - depths(id);
            j = find(d(1:end-1).*d(2:end) <= 0 & ~isnan(d(1:end-1)) & ~isnan(d(2:end)) ...
                & abs(ang(2:end) - ang(1:end-1)) < 0.1);
            if isempty(j), continue; end
            w = d(j)./(d(j) - d(j+1)); w(~isfinite(w)) = 0;
            a = ang(j) + w.*(ang(j+1) - ang(j));
            t = tc(j) + w.*(tc(j+1) - tc(j));
            s = -a;   % arrival elevation, positive up
            [~, best] = min(abs(s - G(ir, id)));
            S(ir, id) = s(best); T(ir, id) = t(best); N(ir, id) = numel(j);
        end
    end
    P.slant = S; P.geom = G; P.bias = S - G; P.tau = T; P.neig = N;
    P.depthest = hdepth - ranges'.*tand(S);
    P.deptherr = P.depthest - depths;
    B.(pth) = P;
end
end

function g = geomslant(pth, r, zt, zh, D)
% straight line slant from the lander to the source, or to its image
switch pth
    case 'D', g = atand((zh - zt)./r);
    case 'S', g = atand((zh + zt)./r);
    case 'B', g = -atand((2*D - zt - zh)./r);
end
end
