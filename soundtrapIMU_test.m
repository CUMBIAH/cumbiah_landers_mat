%Open and plot soundtrap IMU files. 

% binaryfolder = '/Users/jdjm/Dropbox/SMRU_research/2026-27_CUMBIAH/landers/Denmark/lander1/pamguard/PAMBinary/20241005';
binaryfolder = '/Users/jdjm/Library/CloudStorage/Dropbox/SMRU_research/2026-27_CUMBIAH/landers/Denmark/lander2/pamgaurd/PAMBinary_sensor/20241005';

sensdat = loadPamguardBinaryFolder(binaryfolder, 'SoundTrap_Sensor*.pgdf');

%plot heading pitch and roll
sensorient = [[sensdat.heading]; [sensdat.pitch]; [sensdat.roll]]';
senstime = datetime([sensdat.date], 'ConvertFrom', 'datenum');


% Plot the sensor orientation data
figure;
plot(senstime, sensorient(:,1));
hold on;
plot(senstime, sensorient(:,2));
plot(senstime, sensorient(:,3));
hold off;
xlabel('Time');
ylabel('Orientation (degrees)');
title('Sensor Orientation Over Time');
legend show;
grid on;

legend('Heading', 'Pitch', 'Roll')