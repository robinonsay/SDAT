%% Link Budget Analysis & Link Margin
Rs = -147;  %Reciever Sensitivity in dB
Tp = 3;     %Transmitter Power in dB
d = 1000;   %Distance in km
G = 14.3;   %Gain of Antenna going to be doubled for transmitter and reciever antenna gainsin dB
f = 8.4;    %Frequency in GHz

%Calculating Free Space Loss to use in Link Margin
Lfs = 92.45 + (20*log10(d)) + (20*log10(f));

%Calculating Link Budget
LB =G + G + Tp - Lfs;

str = ['The Link Budget for a distance of ', num2str(d), ' km is: ', num2str(LB), ' dB.'];
disp(str)   %Showing the text for Link Budget of the Distance.

%Calculating Link Margin
LM = LB - Rs;

str = ['The Link Margin for a distance of ', num2str(d), ' km is: ', num2str(LM), ' dB.'];
disp(str)   %Showing the text for Link Margin and Distance.

%Showing a graph of the Distance v Link Margin with the Link Margin Minimum
%added in as a horizontal line
d = (0:2000);
maxd = 10^((G+G+Tp-Rs-92.45-20*log10(f)-3)/20);    %Calculating Maximum distance LM is 3
Lfs = 92.45 + (20*log10(d)) + (20*log10(f));
LM = -Rs + G + G + Tp - Lfs;
plot(d,LM);
yline(3, '-', 'Minimum Link Margin')
xline(maxd, '-', 'Maximum Distance')
ylabel('Link Margin (dB)'); xlabel('Distance (km)')

str = ['The graph shows Link Margin versus Distance as well as the Minimum Link Margin of 3 and the Maximum Distance of ', num2str(maxd), ' to be above the Minimum Link Margin.'];
disp(str)


