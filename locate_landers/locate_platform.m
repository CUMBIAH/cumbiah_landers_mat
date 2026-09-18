%Locate a sensor platform on the seabed from boat calibrations
%
% Pick a country, a lander and a deployment, let GETLANDERDEPLOYMENTINFO and
% GETLANDERPATHS find the data, hand the record to LOCATEPLATFORM and
% plot what comes back. The calculation itself lives in LOCATEPLATFORM,
% which draws nothing - all the figures are here.
clear
clear global
close all

%which country, which lander and which deployment. Lander and deployment
%numbers are per country - for Denmark, landers 1-9 and deployments
%1 = Oct 24, 2 = Feb 25, 3 = June 25. Not every lander was in every
%deployment - ask for one that never happened and GETLANDERDEPLOYMENTINFO
%says which ones it does have.
country      = 'Denmark';
landernumber = 1;
deployment   = 1;

[startTime, ~, serialnumber] = getlanderdeploymentinfo(landernumber, deployment, country);
data = getlanderpaths(serialnumber, startTime);

%LOCATEPLATFORM takes the calibration clicks from the deployment day, the
%boat GPS track and the drop position straight out of DATA. The depth is not
%in the spreadsheet so it is passed here.
% results = locateplatform(data, 'depth', 17, 'setlocation', [54.747839655666297, 12.533771685747112]);
% results = locateplatform(data, 'depth', 17);
 results = locateplatform(data, 'depth', 17, 'gridlims', [-40 40], 'gridcenter', data.droplocation);


%pull the results apart for plotting
location         = results.location;
locationfine     = results.locationfine;
dropgpsloc       = results.droplocation;
clickbearings    = results.clickbearings;
clkgeobearings   = results.clkgeobearings;
srcclklocationst = results.srcclklocations;
chi2surf         = results.chi2surf;
chi2surffine     = results.chi2surffine;
headingoffset    = results.headingoffset;
headingstd       = results.headingstd;
hprfinal         = results.hprfinal;

disp(['Platform heading: ' num2str(headingoffset) ' +/- ' num2str(headingstd) ' degrees'])
disp(['Fine location: ' num2str(locationfine, 8) ' chi2: ' num2str(results.chi2fine)])
disp(['Platform heading, pitch and roll: ' num2str(hprfinal) ' degrees'])
[d1] = latLong2meters(locationfine(1), locationfine(2), dropgpsloc(1), dropgpsloc(2));
[d2] = latLong2meters(locationfine(1), locationfine(2), data.retrievelocation(1), data.retrievelocation(2));

disp(['Platform  is : ' num2str(d1) 'm from drop location'])
disp(['Platform  is : ' num2str(d2) 'm from retrive location'])

% chi2 against the SoundTrap clock offset, the lowest being the offset taken
figure(3)
clf
scatter(results.rtcoffset, results.chi2offsets);
ylabel('chi2')
xlabel('Time offset (seconds)')
title(['Lowest time offset ' num2str(results.rtctimeoffset) 's'])

% plot the grid search surface for the lowest chi2 angle. There is no
% surface when the location was forced with 'setlocation'.
if ~isempty(chi2surf)
    figure(4)
    clf
    [h1, hloc] = plot_chi2_surf(chi2surf, srcclklocationst, location);
    hold on
    h2 = scatter3(srcclklocationst(:,3), srcclklocationst(:,2),...
        (max(max(chi2surf.chi2))+10)*ones(length(srcclklocationst(:,3)), 1),'.');

    h3drop = scatter3(dropgpsloc(:,2), dropgpsloc(:,1), 300, 'filled');
    title({['Min chi2: ' num2str(results.chi2)], ['Calculated location: ' num2str(location)], ...
        ['Time offset: ' num2str(results.rtctimeoffset)]})

    legend([hloc,h3drop, h2], {'Calculatedlocation', 'Dropped location', 'Detected transients'})

    view([0,90])

    % clim([0,5])
    set(gca, 'FontSize', 12)
end

% plot the bearings of the source compared to the bearings of the
% geo referenced clicks.
figure(5)
clf
h2 = plot_clk_src_bearings(location, ...
    [clickbearings(:,1), rad2deg(clkgeobearings)], srcclklocationst);
set(gca, 'FontSize', 14)

% plot the difference in bearings over time. The bearings are geo referenced
% assuming the platform lies flat and points north, so this difference is the
% heading and its circular mean is HEADINGOFFSET.
figure(6)
clf
scatter(datetime(clickbearings(:,1), 'ConvertFrom', 'datenum'), results.clkangdiff, '.')
hold on
yline(headingoffset, 'r', 'LineWidth', 2)
hold off
ylabel('Bearing difference (degrees)')
xlabel('Time')
title(['Platform heading: ' num2str(headingoffset) ' +/- ' num2str(headingstd) ' degrees'])
set(gca, 'FontSize', 12)

% plot the fine grid search surface
figure(7)
clf
finelims = [minmax(chi2surffine.latgrid) minmax(chi2surffine.longrid)];
[h1, hloc] = plot_chi2_surf(chi2surffine, srcclklocationst, locationfine, finelims);
hold on
h3drop = scatter3(dropgpsloc(:,2), dropgpsloc(:,1), max(max(chi2surffine.chi2)), 'filled');
hcoarse = scatter3(location(2), location(1), max(max(chi2surffine.chi2)), 'filled');
title({['Min chi2: ' num2str(results.chi2fine)], ['Fine location: ' num2str(locationfine, 8)], ...
    ['Heading, pitch, roll: ' num2str(hprfinal)]})
legend([hloc, hcoarse, h3drop], {'Fine location', 'Coarse location', 'Dropped location'})
view([0,90])
set(gca, 'FontSize', 12)

% plot the chi2 of each orientation, minimised over all the positions
figure(8)
clf
subplot(1,3,1)
plot(chi2surffine.headings, squeeze(min(min(chi2surffine.hprchi2, [], 3), [], 2)))
xlabel('Heading (degrees)')
ylabel('chi2')
subplot(1,3,2)
plot(chi2surffine.pitches, squeeze(min(min(chi2surffine.hprchi2, [], 3), [], 1)))
xlabel('Pitch (degrees)')
subplot(1,3,3)
plot(chi2surffine.rolls, squeeze(min(min(chi2surffine.hprchi2, [], 2), [], 1)))
xlabel('Roll (degrees)')

% plot the corrected bearings against the bearings to the source
figure(9)
clf
[h2, srcbearingsfine] = plot_clk_src_bearings(locationfine, ...
    [clickbearings(:,1), rad2deg(results.clkgeobearingsfinal)], srcclklocationst);
set(gca, 'FontSize', 14)
