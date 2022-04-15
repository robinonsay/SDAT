%% Constants
SEED = 3165;
MAX_DIST_TO_MARS = 400.4e9;
%% Import Config Filasde
config_name = input("Config File Name? ", "s");
run_description = input("Run Description? ", "s");
if isempty(config_name)
    config_name = "default_config.json";
end
fid = fopen(config_name);
config_json = char(fread(fid, inf)');
fclose(fid);
config = jsondecode(config_json);
% Set random number generator seed
rng(SEED);
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
%% Channel Setup
% Specify channel model
if contains(config.Channel.Model, "awgn", "IgnoreCase", true)
    channel = comm.AWGNChannel;
elseif contains(config.Channel.Model, "rician", "IgnoreCase", true)
    pathDelays = eval(config.Channel.Path_Delays);
    averagePathGains = eval(config.Channel.Average_Path_Gains);
    kFactor = eval(config.Channel.K_Factor);
    directPathDopplerShift = eval(config.Channel.Direct_Path_Doppler_Shift);
    directPathInitialPhase = eval(config.Channel.Direct_Path_Initial_Phase);
    maxDopplerShift = config.Channel.Maximum_Doppler_Shift;
    channel = comm.RicianChannel("PathDelays", pathDelays, ...
        "AveragePathGains", averagePathGains, ...
        "KFactor", kFactor, ...
        "DirectPathDopplerShift", directPathDopplerShift, ...
        "DirectPathInitialPhase", directPathInitialPhase, ...
        "MaximumDopplerShift", maxDopplerShift);
end
%% Modulation Setup
% Specify modulation scheme
fprintf("Modulation Scheme:\n");
disp(config.Mod_Scheme);
if contains(config.Mod_Scheme.Method, "M-PSK", 'IgnoreCase', true)
    M = config.Mod_Scheme.M;  % Modulation Alphabet
    k = log2(M);  % Bits per symbol
    % Define PSK modulator
    modulator = comm.PSKModulator('ModulationOrder', M, 'BitInput',true);
    % Define PSK demodulator
    demodulator = comm.PSKDemodulator('ModulationOrder', M, 'BitOutput', true);
    % Initialize Channel Model
    if contains(config.Channel.Model, "awgn", "IgnoreCase", true)
        channel.BitsPerSymbol = k;
    end
else
    error("Invalid Modulation Scheme");
end
%% Pulse Shaping Filter Setup
% Define RRC Pulse Shaping Matched Filters
txfilter = comm.RaisedCosineTransmitFilter("RolloffFactor", config.RRC_Filter_Props.RollOff, ...
    "FilterSpanInSymbols", config.RRC_Filter_Props.FilterSpanInSymbols, ...
    "OutputSamplesPerSymbol", config.RRC_Filter_Props.SamplesPerSymbol);
rxfilter = comm.RaisedCosineReceiveFilter("RolloffFactor", config.RRC_Filter_Props.RollOff, ...
    "FilterSpanInSymbols", config.RRC_Filter_Props.FilterSpanInSymbols, ...
    "InputSamplesPerSymbol", config.RRC_Filter_Props.SamplesPerSymbol, ...
    "DecimationFactor", config.RRC_Filter_Props.SamplesPerSymbol);
filterDelay = k * txfilter.FilterSpanInSymbols;
% Define BER and EVM Calculators
ber = comm.ErrorRate("ResetInputPort", true);
%% Setup FEC
fprintf("FEC:\n");
disp(config.FEC);
if contains(config.FEC.Method, "LDPC", "IgnoreCase", true)
    % Valid Code Rates: 1/4, 1/3, 2/5, 1/2, 3/5,
    % 2/3, 3/4, 4/5, 5/6, 8/9, or 9/10
    codeRate = eval(config.FEC.Code_Rate);
    % Use DVBS2 Standard for simplicity
    H = dvbs2ldpc(codeRate);
    maxnumiter = 50;
    cfgLDPCEnc = ldpcEncoderConfig(H);
    cfgLDPCDec = ldpcDecoderConfig(cfgLDPCEnc);
    bits_per_frame = cfgLDPCEnc.NumInformationBits;
    num_frames = (10/config.Max_BER) / bits_per_frame + 1;
    demodulator.DecisionMethod = 'Approximate log-likelihood ratio';
else
    % Default to 1 KB frames
    codeRate = 1;
    bits_per_frame = 2^10;
    num_frames = (10/config.Max_BER) / bits_per_frame + 1;
end
%% Eb/No and SNR
%Calculate Eb/No and SNR-------------------------
% https://www.dsprelated.com/showarticle/168.php?msclkid=dd85b998a7bb11ec8b9235e20eafce8c
Rs = config.Target_Data_Rate/k;
Rb = config.Target_Data_Rate;
BWn = 2*config.Freq+config.Bandwidth;
Ps = minLB;
No = (-231:-171)';
Es = Ps - 10*log10(Rs);
Eb = Es - 10*log10(k)- 10*log(codeRate);
EbNo = Eb - No;
SNR = EbNo + 10*log10(Rs) + 10*log10(k) + 10*log10(codeRate) - 10*log10(BWn);
%-------------------------------------------------
% Initialize output vectors
berVec = zeros(length(EbNo),3);
errStats = zeros(1,3);
%% Simulation
if contains(config.Channel.Model, "awgn", "IgnoreCase", true)
    % Theoretical BER from Eb/No
    [berTheory, serTheory] = berawgn(EbNo, 'psk', M, 'nondiff');
    for i = 1:length(SNR)
        % Set EbNo for AWGN channel
        channel.EbNo = EbNo(i);
        snr = SNR(i);
        if contains(config.FEC.Method, "LDPC", "IgnoreCase", true)
            % Set demodulator variance for Approx. LLR demodulation
            demodulator.Variance = 1/10^(snr/10);
        end
        % Send Frames
        for counter = 1:num_frames
            if contains(config.FEC.Method, "LDPC", "IgnoreCase", true)
                % Encode Data
                data_in = randi([0 1], bits_per_frame, 1, "int8");
                encodedData = ldpcEncode(data_in, cfgLDPCEnc);
            else
                data_in = randi([0 1], bits_per_frame, 1);
                encodedData = data_in;
            end
            % Pad data with zeros because of filter delay
            paddedEncodedData = [encodedData; zeros(filterDelay,1)];
            % Modulate signal
            modTx = modulator(paddedEncodedData);
            % RRC Filter signal
            txSig = txfilter(modTx);
            % Send signal over channel
            rxSig = channel(txSig);
            % Matched RRC filter to get symbols
            modRx = rxfilter(rxSig);
            % Demodulate signal
            demodRx = demodulator(modRx);
            % Remove padded data
            demodRx(1:filterDelay) = [];
            if contains(config.FEC.Method, "LDPC", "IgnoreCase", true)
                % Decode Data
                data_out = ldpcDecode(demodRx, cfgLDPCDec, maxnumiter);
            else
                data_out = demodRx;
            end
            % Calculate stats
            errStats = ber(data_in, data_out, false);
        end
        % Save stats and reset calculators
        berVec(i, :) = errStats;
        errStats = ber(data_in, data_out, true);  % Reset Calculator
    end
elseif contains(config.Channel.Model, "rician", "IgnoreCase", true)
    % Send Frames
    for counter = 1:num_frames
        if contains(config.FEC.Method, "LDPC", "IgnoreCase", true)
            % Encode Data
            data_in = randi([0 1], bits_per_frame, 1, "int8");
            encodedData = ldpcEncode(data_in, cfgLDPCEnc);
        else
            data_in = randi([0 1], bits_per_frame, 1);
            encodedData = data_in;
        end
        % Pad data with zeros because of filter delay
        paddedEncodedData = [encodedData; zeros(filterDelay,1)];
        % Modulate signal
        modTx = modulator(paddedEncodedData);
        % RRC Filter signal
        txSig = txfilter(modTx);
        % Send signal over channel
        rxSig = channel(txSig);
        % Matched RRC filter to get symbols
        modRx = rxfilter(rxSig);
        % Demodulate signal
        demodRx = demodulator(modRx);
        % Remove padded data
        demodRx(1:filterDelay) = [];
        if contains(config.FEC.Method, "LDPC", "IgnoreCase", true)
            % Decode Data
            data_out = ldpcDecode(demodRx, cfgLDPCDec, maxnumiter);
        else
            data_out = demodRx;
        end
        % Calculate stats
        errStats = ber(data_in, data_out, false);
    end
    fprintf("BER for Rician Channel: %d\n", errStats(1));
end
%% Plot Figures
% Plot BER
if contains(config.Channel.Model, "awgn", "IgnoreCase", true)
    berFigure = figure;
    semilogy(EbNo,berVec(:,1), "Marker", "*");
    hold on;
    semilogy(EbNo,berTheory);
    ylim([config.Max_BER^2 1]);
    yline(config.Max_BER, '-', 'Maximum BER');
    title(['BER vs Eb/No: ', run_description]);
    legend('Simulation','AWGN Theory (no FEC)','Location','Best');
    xlabel('Eb/No (dB)');
    ylabel('Bit Error Rate');
    annotation("textbox", [.2 .5 .6 .3], ...
        "String", ["Expected EbNo" EbNo(1)], 'FitBoxToText', 'on');
    grid on;
    hold off;
    saveas(berFigure, "Figures/berFigure.png");
    % Calculate Spectral Efficiency
    SNR_dec = 10.^(SNR/10);
    capacity = config.Bandwidth * log2(1 + SNR_dec);
    specFigure = figure;
    semilogy(SNR, capacity);
    hold on;
    title(['Spectral Efficiency ', run_description]);
    xlabel('SNR (dB)');
    ylabel('Capacity (bits/sec)');
    grid on;
    hold off;
    saveas(specFigure, "Figures/specFigure.png");
end
% Plot Link Margin
d = (maxR-maxR/2:maxR/100:maxR+maxR/2);
Lfs = fspl(d, lambda);
LB = config.Tx_Power + config.Tx_Ant_Gain + config.Rx_Ant_Gain - Lfs;
LM = LB - config.Receiver_Sensitivity;
LMFigure = figure;
plot(d,LM);
title(['Link Margin vs Distance: ', run_description]);
xline(maxR, '-', 'Maximum Distance');
yline(config.Min_Link_Margin, '-', 'Minimum Link Margin');
ylabel('Link Margin (dB)'); xlabel('Distance (m)');
saveas(LMFigure, "Figures/LMFigure.png");
