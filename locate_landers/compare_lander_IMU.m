%The landers have their rotation and position calculated by a grid search.
%The SoundTrap should be attached to the frame in the same way for each
%lander and therefore the heading and pitch should be related to the grid
%search loctions. 

clear

country    = 'Denmark';
landers    = [1 2 3];
deployment = 1; 

denmarkdir  = getlandersuperfolder(country);

nlander = numel(landers);

%% Locate the landers

%the deployment records, for the drop positions and the GPS track
for i = 1:nlander
    [startTime, ~, serialnumber] = getlanderdeploymentinfo(landers(i), deployment, country);
    data(i) = getlanderpaths(serialnumber, startTime);

    binaryfolder = [data(i).binaryfolder 'sud_sensor'];

    %load up the data

end

%Now load up the PAMBinary data for the sud IMU 


