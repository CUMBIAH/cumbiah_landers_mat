function [h2, h3, c] = plot_loctrack_landers(loctracks, landerxyz, meshdata, varargin)
%PLOT_LOCTRACK_LANDERS Plots localisation tracks over the seabed with the landers.
%
%   PLOT_LOCTRACK_LANDERS(LOCTRACKS, LANDERXYZ, MESHDATA) plots the
%   localised tracks of LOCALISEPORPOISES, coloured by time, over the
%   bathymetry around a lander array. It is the lander version of the gill
%   net plots (PLOT_LOCTRACK_BATHY, PLOT_LOCTRACK_CORNWALL): the same
%   tracks and seabed, with the landers in place of the net.
%
%   LOCTRACKS is a struct array of localisation tracks (xh, loctracktimes,
%   datestart, dateend), LANDERXYZ the [n x 3] positions of the landers
%   [east north up] (m) and MESHDATA the seabed as x, y and z meshes, in
%   the format used by the localisation code.
%
%   Name-value parameters:
%     'landernumbers' - number each lander is labelled with [1:n]
%     'timelims'      - time limits of the colour scale (s) [the tracks']
%     'lims'          - half width of the area plotted (m) [200]
%     'showlegend', 'showcolorbar', 'showtitle' - [true]
%     'timecmap'      - colour map of the tracks ['Jet']
%
%   See also LOCALISEPORPOISES, PLOT_LOC_TRACK, LOCATE_ARRAY.

p = inputParser;
addParameter(p, 'landernumbers', [], @isnumeric);
addParameter(p, 'timelims', [], @isnumeric);
addParameter(p, 'lims', 200, @isnumeric);
addParameter(p, 'showlegend', true, @islogical);
addParameter(p, 'showcolorbar', true, @islogical);
addParameter(p, 'showtitle', true, @islogical);
addParameter(p, 'timecmap', 'Jet');
parse(p, varargin{:});

landernumbers = p.Results.landernumbers;
timelims      = p.Results.timelims;
lims          = p.Results.lims;

nlander = size(landerxyz, 1);
if isempty(landernumbers)
    landernumbers = 1:nlander;
end
if isempty(timelims)
    alltimes = vertcat(loctracks.loctracktimes);
    timelims = [min(alltimes) max(alltimes)];
end

hold on
s1 = surf(meshdata.x, meshdata.y, meshdata.z);
s1.EdgeColor = 'none';
% grey over the depths that are plotted, not the whole mesh. Set before the
% tracks are plotted: the time colour bar takes its ticks from these limits
inview = abs(meshdata.x) <= lims & abs(meshdata.y) <= lims;
zrange = [min(meshdata.z(inview)) max(meshdata.z(inview))];
if numel(zrange) == 2 && diff(zrange) > 0
    clim(zrange + [-1 1]*diff(zrange))
end

% the landers, each on a line up from the seabed below it
zbed = interp2(meshdata.x, meshdata.y, meshdata.z, landerxyz(:,1), landerxyz(:,2));
for i = 1:nlander
    if ~isnan(zbed(i))
        plot3(landerxyz([i i],1), landerxyz([i i],2), [zbed(i) landerxyz(i,3)], 'k', 'LineWidth', 1.5);
    end
    text(landerxyz(i,1), landerxyz(i,2), landerxyz(i,3) + 1, sprintf('  %d', landernumbers(i)), ...
        'FontWeight', 'bold');
end
h3 = scatter3(landerxyz(:,1), landerxyz(:,2), landerxyz(:,3), 60, 'filled', ...
    'MarkerEdgeColor', 'k', 'MarkerFaceColor', 'g');

hold on
[h2, c] = plot_loc_track(loctracks, 'timelimits', timelims, 'showtitle', ...
    p.Results.showtitle, 'showcolourbar', p.Results.showcolorbar, 'timecmap', p.Results.timecmap);
colormap('Gray')
xlim([-lims, lims])
ylim([-lims, lims])
xlabel('Eastings (m)')
ylabel('Northings (m)')
zlabel('Depth (m)')
hold off

if p.Results.showlegend
    legend([h2, h3], {'Porpoise Track', 'Landers'});
end

end
