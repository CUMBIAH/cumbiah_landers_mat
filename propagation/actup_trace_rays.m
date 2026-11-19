function rays = actup_trace_rays(z, c, srcdepth, angles, varargin)
%ACTUP_TRACE_RAYS Trace a fan of rays with the ACTUP BELLHOP(M) ray tracer.
%
%   RAYS = ACTUP_TRACE_RAYS(Z, C, SRCDEPTH, ANGLES) traces rays from a
%   source at SRCDEPTH (m) through the range independent sound speed
%   profile C(Z) using the MATLAB port of BELLHOP shipped with AcTUP v2.2L
%   (AT/Matlab/Bellhop: readenv, read_bell, trace, step, reflect). A
%   BELLHOP .env file is written to a temporary folder, read back with the
%   ACTUP readers so the profile is set up exactly as BELLHOP sets it up
%   (C-linear), and the rays are then traced with the ACTUP TRACE.
%
%   Z is the profile depth (m, increasing, Z(1) = 0 the sea surface and
%   Z(end) the seabed), C the sound speed (m/s). ANGLES are launch angles
%   (deg, BELLHOP convention: positive is DOWN, towards the seabed). The
%   surface is a pressure release boundary and the seabed is rigid, so
%   every reflection is kept (only the ray geometry is used here).
%
%   By reciprocity the path from a source at SRCDEPTH launched at angle A
%   is the path a click takes from any point on that ray back to a
%   receiver at SRCDEPTH, arriving from elevation -A (positive up).
%
%   RAYS is a struct array, one per angle, with fields
%       angle  - launch angle (deg, positive down)
%       r, z   - ray path, range and depth (m)
%       tau    - travel time along the ray (s)
%       nbnc   - number of boundary reflections before each point
%       bnc    - boundary of each reflection, 'S' surface or 'B' seabed
%
%   Name-value options:
%       'maxrange' - rays are traced to this range (m) [300]
%       'step'     - BELLHOP step size (m) [0.5]
%       'chunk'    - rays traced together (memory) [100]
%       'actup'    - the ACTUP folder [~/MATLAB-Drive/MATLAB/ACTUP]
%       'freq'     - nominal frequency for the .env file (Hz) [130000]
%       'directonly' - stop each ray soon after its direct leg ends (for
%                    steep rays, which would otherwise bounce between the
%                    surface and the seabed thousands of times) [false]
%
%   See also SLANT_REFRACTION_BIAS, LOAD_SITE_SVPS.

p = inputParser;
p.addParameter('maxrange', 300);
p.addParameter('step', 0.5);
p.addParameter('chunk', 100);
p.addParameter('actup', fullfile(getenv('HOME'), 'MATLAB-Drive', 'MATLAB', 'ACTUP'));
p.addParameter('freq', 130000);
p.addParameter('directonly', false);
p.parse(varargin{:});
opt = p.Results;

z = z(:); c = c(:);
if z(1) ~= 0
    error('actup_trace_rays:surface', 'The profile must start at the surface (Z(1) = 0).');
end
D = z(end);

bellhopdir = fullfile(opt.actup, 'AcTUP v2.2L', 'AT', 'Matlab', 'Bellhop');
if ~isfolder(bellhopdir)
    error('actup_trace_rays:noACTUP', 'ACTUP BELLHOP(M) not found at %s', bellhopdir);
end

% ---- write a BELLHOP environment file -----------------------------------
tmp = tempname;
mkdir(tmp);
cleanTmp = onCleanup(@() rmdir(tmp, 's'));
envfile = fullfile(tmp, 'svp.env');
fid = fopen(envfile, 'w');
fprintf(fid, '''CUMBIAH lander SVP''\n');
fprintf(fid, '%.1f\n', opt.freq);
fprintf(fid, '1\n');
fprintf(fid, '''CVF''\n');                       % C-linear, vacuum top, dB/wavelength
fprintf(fid, '0 0.0 %.3f\n', D);
for i = 1:numel(z)
    fprintf(fid, '%.3f %.4f /\n', z(i), c(i));
end
fprintf(fid, '''R'' 0.0\n');                     % rigid seabed (geometry only)
fprintf(fid, '1\n%.3f /\n', srcdepth);           % source (the lander hydrophone)
fprintf(fid, '1\n%.3f /\n', srcdepth);           % receivers - unused for a ray run
fprintf(fid, '1\n%.4f /\n', opt.maxrange/1000);
fprintf(fid, '''R''\n');                         % ray trace run
fprintf(fid, '2\n%.4f %.4f /\n', min(angles), max(angles));
fprintf(fid, '%.4f %.3f %.4f\n', opt.step, D + 1, opt.maxrange/1000);
fclose(fid);

% ---- set up the environment with the ACTUP readers ----------------------
oldpath = addpath(bellhopdir);          % note: shadows the builtin TRACE
restorePath = onCleanup(@() path(oldpath));

global SSP Bdry ray Nsteps omega alpha Nbeams %#ok<GVMIS>
global xTop tTop nTop NatiPts xBot tBot nBot NbtyPts %#ok<GVMIS>
clear global xTop tTop nTop NatiPts xBot tBot nBot NbtyPts
global xTop tTop nTop NatiPts xBot tBot nBot NbtyPts %#ok<GVMIS,REDEFGG>

evalc('[~, freq, Bdry, fid] = readenv(envfile);');
evalc('Pos = readsdrd(fid);');
evalc('[Pos.r.range, Pos.Nrr] = readr(fid);');
evalc(['[~, ~, ~, deltas, zBox, rBox, ~, ~, RunType, BeamType] = ' ...
    'read_bell(fid, freq, Bdry.Bot.depth, Bdry.Top.depth, Pos.r.range(Pos.Nrr));']);
evalc('readati('''', '' '', Bdry.Top.depth, rBox);');
evalc('readbty('''', '' '', Bdry.Bot.depth, rBox);');
evalc('readrc('''', '''', Bdry.Top.Opt(2:2), Bdry.Bot.Opt(1:1));');
omega = 2*pi*freq;

% ---- trace the rays in chunks (TRACE keeps every step of every ray) -----
angles = angles(:);
xs = [0.0 srcdepth];
rays = repmat(struct('angle', [], 'r', [], 'z', [], 'tau', [], 'nbnc', [], 'bnc', ''), numel(angles), 1);
for k0 = 1:opt.chunk:numel(angles)
    k = k0:min(k0 + opt.chunk - 1, numel(angles));
    nb = numel(k);
    a = deg2rad(angles(k));
    alpha = a; Nbeams = nb;
    ray = []; Nsteps = [];
    rBoxk = rBox;
    amin = min(abs(angles(k)));
    if opt.directonly && amin > 15
        % a steep ray is barely bent by a shallow water profile (a few m/s
        % of sound speed change only turns rays below ~10 deg), so its
        % direct leg ends within a little more than the straight line
        % range to a boundary: the rest of the ray is not needed
        rBoxk = min(rBox, 2*D/tand(amin) + 2);
    end
    evalc('trace(1:nb, deltas, xs, a, ones(nb,1), BeamType, zBox, rBoxk, Bdry.Bot.Opt, RunType);');
    ns = max(Nsteps);
    X = nan(ns, nb); Zr = X; Tz = X; Tau = X;
    for s = 1:ns
        xi = ray(s).x;
        n = min(size(xi, 1), nb);
        X(s, 1:n) = xi(1:n, 1)';
        Zr(s, 1:n) = xi(1:n, 2)';
        tt = ray(s).Tray; m = min(size(tt, 1), nb);
        Tz(s, 1:m) = tt(1:m, 2)';
        ta = ray(s).tau; m = min(numel(ta), nb);
        Tau(s, 1:m) = ta(1:m)';
    end
    for j = 1:nb
        n = Nsteps(j);
        rj = X(1:n, j); zj = Zr(1:n, j); tzj = Tz(1:n, j);
        % a reflection is where the vertical direction flips at a boundary
        flip = [false; sign(tzj(2:end)) ~= sign(tzj(1:end-1))];
        atS = zj < 1e-6;
        atB = zj > D - 1e-6;
        hit = flip & (atS | atB);
        rays(k(j)).angle = angles(k(j));
        rays(k(j)).r = rj;
        rays(k(j)).z = zj;
        rays(k(j)).tau = Tau(1:n, j);
        % the reflection point belongs to the incoming leg
        rays(k(j)).nbnc = [0; cumsum(hit(1:end-1))];
        b = repmat('S', 1, sum(hit));
        b(atB(hit)) = 'B';
        rays(k(j)).bnc = b;
    end
end
clear global ray
end
