MAX_DIST_TO_MARS = 400.4e9;
%% Import Config File
config_name = input("Config File Name? ", "s");
if isempty(config_name)
    config_name = "default_config.json";
end
fid = fopen(config_name);
config_json = char(fread(fid, inf)');
fclose(fid);
config = jsondecode(config_json);
%% Link Margin & Link Budget
% Distance from transmitter to reciever
R = config.Target_Dist;  % Transmission Distance
lambda = physconst('LightSpeed')/config.Freq;  % Wavelength
Lfs = fspl(R, lambda);  % Free-space path loss
% Calculate Link Margin and Link Budget
LB = config.Tx_Power + config.Tx_Ant_Gain + ...
    config.Rx_Ant_Gain - Lfs;  % Link Budget Calc
fprintf("Link Budget (%.2e m): %.2e dB\n", R, LB);
LM = LB - config.Receiver_Sensitivity;  % Link Margin Calc
fprintf("Link Margin (%.2e m): %.2e dB\n", R, LM);
% Recalculate LB/LM for max distance
maxLfs = config.Tx_Power + config.Tx_Ant_Gain + config.Rx_Ant_Gain - ...
    config.Min_Link_Margin - config.Receiver_Sensitivity;  % The max allowable Lfs
% Assuming an omnidirectional radiation pattern...
maxR = (lambda/(4*pi))*10^(maxLfs/20);  % Max distance given maxLfs
fprintf("Comm. Range: %.2e m\n", maxR);
fprintf("Min. Number of Nodes: %d\n", MAX_DIST_TO_MARS/maxR);
% Link budget at maximum distance
minLB = config.Tx_Power + config.Tx_Ant_Gain + config.Rx_Ant_Gain - maxLfs;
% Plot Link Margin
d = (maxR-maxR/2:maxR/100:maxR+maxR/2);
Lfs = fspl(d, lambda);
LB = config.Tx_Power + config.Tx_Ant_Gain + config.Rx_Ant_Gain - Lfs;
LM = LB - config.Receiver_Sensitivity;
LMFigure = figure;
plot(d,LM);
title('Link Margin vs Distance');
xline(maxR, '-', 'Maximum Distance');
yline(config.Min_Link_Margin, '-', 'Minimum Link Margin');
ylabel('Link Margin (dB)'); xlabel('Distance (m)');
saveas(LMFigure, "Figures/LMFigure.png");