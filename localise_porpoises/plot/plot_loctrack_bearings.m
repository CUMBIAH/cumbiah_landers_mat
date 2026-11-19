function plot_loctrack_bearings(loctracks, landerxyz, clicks, varargin)
%PLOT_LOCTRACK_BEARINGS Plots the bearings each lander heard against those of the localised tracks.
%
%   PLOT_LOCTRACK_BEARINGS(LOCTRACKS, LANDERXYZ, CLICKS) plots, in a new
%   tiled layout in the current figure, one row per lander: the true
%   horizontal bearing (left) and slant angle (right) of every click the
%   lander heard against time, in grey, and over them the bearing and slant
%   angle from the lander to each localised position, coloured by time. If
%   the localisation is right the coloured points lie on the grey ones for
%   every lander that heard the animal - a check of the lander positions
%   and orientations as much as of the tracks.
%
%   LOCTRACKS, LANDERXYZ and CLICKS are as for PLOT_LOCTRACK_FRAME: CLICKS
%   has one element per lander with t (datenum, on the reference lander's
%   clock), bearing and slant (deg).
%
%   Name-value parameters:
%     't0'            - datenum the times are from [the first datestart]
%     'timelims'      - time limits of the plot and colour scale (s from T0)
%                       [the tracks']
%     'landernumbers' - number of each lander [1:n]
%     'timecmap'      - colour map of the tracks ['Jet']
%
%   See also PLOT_LOCTRACK_FRAME, PLOT_LOCTRACK_ARRAY, LOCALISEPORPOISES.

p = inputParser;
addParameter(p, 't0', [], @isnumeric);
addParameter(p, 'timelims', [], @isnumeric);
addParameter(p, 'landernumbers', [], @isnumeric);
addParameter(p, 'timecmap', 'Jet');
parse(p, varargin{:});

nl = size(landerxyz, 1);
landernumbers = p.Results.landernumbers;
if isempty(landernumbers)
    landernumbers = 1:nl;
end
t0 = p.Results.t0;
if isempty(t0)
    t0 = min([loctracks.datestart]);
end
% every localised point, in s from T0
pos = zeros(3, 0);
tpos = zeros(1, 0);
for i = 1:numel(loctracks)
    pos = [pos, loctracks(i).xh(1:3,:)]; %#ok<AGROW>
    tpos = [tpos, loctracks(i).loctracktimes(:)' + (loctracks(i).datestart - t0)*86400]; %#ok<AGROW>
end
timelims = p.Results.timelims;
if isempty(timelims)
    timelims = [min(tpos) max(tpos)];
end
cmap = colormap(p.Results.timecmap);
ci = round(1 + (size(cmap, 1) - 1)*min(max((tpos - timelims(1))/diff(timelims), 0), 1));

tl = tiledlayout(nl, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
for d = 1:nl
    tclk = (clicks(d).t - t0)*86400;
    in = tclk >= timelims(1) & tclk <= timelims(2);
    % from the lander to each localised position
    v = pos - landerxyz(d,:)';
    bearing = mod(atan2d(v(1,:), v(2,:)), 360);
    slant = atan2d(v(3,:), hypot(v(1,:), v(2,:)));

    nexttile
    scatter(tclk(in), mod(clicks(d).bearing(in), 360), 6, [0.6 0.6 0.6], 'filled');
    hold on
    scatter(tpos, bearing, 10, cmap(ci,:), 'filled');
    hold off
    ylim([0 360])
    yticks(0:90:360)
    xlim(timelims)
    ylabel(sprintf('Lander %d bearing (deg)', landernumbers(d)))
    box on

    nexttile
    scatter(tclk(in), clicks(d).slant(in), 6, [0.6 0.6 0.6], 'filled');
    hold on
    scatter(tpos, slant, 10, cmap(ci,:), 'filled');
    hold off
    ylim([-90 90])
    yticks(-90:45:90)
    xlim(timelims)
    ylabel('Slant (deg)')
    box on
    if d == 1
        legend({'Clicks', 'Localised track'}, 'Location', 'best');
    end
end
xlabel(tl, sprintf('Time from %s (s)', datestr(t0, 'yyyy-mm-dd HH:MM:SS')))

end
