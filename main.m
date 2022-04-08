%% Constants
SEED = 3165;
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
%% Setup
% Set random number generator seed
rng(SEED);
% Distance from transmitter to reciever
R = config.Target_Dist;  % Transmission Distance
lambda = physconst('LightSpeed')/config.Freq;  % Wavelength
Lfs = fspl(R, lambda);  % Free-space path loss
% Calculate Link Margin and Link Budget
LB = config.Tx_Power + config.Ant_Gain * 2 - Lfs;  % Link Budget Calc
fprintf("Link Budget (%.2e m): %.2e dB\n", R, LB);
LM = LB - config.Receiver_Sensitivity;  % Link Margin Calc
fprintf("Link Margin (%.2e m): %.2e dB\n", R, LM);
% Recalculate LB/LM for max distance
maxLfs = config.Tx_Power + 2*config.Ant_Gain - config.Min_Link_Margin ...
    - config.Receiver_Sensitivity;  % The max allowable Lfs
% Assuming an omnidirectional radiation pattern...
maxR = (lambda/(4*pi))*10^(maxLfs/20);  % Max distance given maxLfs
fprintf("Comm. Range: %.2e m\n", maxR);
fprintf("Min. Number of Nodes: %d\n", MAX_DIST_TO_MARS/maxR);
% Link budget at maximum distance
minLB = config.Tx_Power + config.Ant_Gain * 2 - maxLfs;
% Specify channel model
if contains(config.Channel, "awgn", "IgnoreCase", true)
    channel = comm.AWGNChannel;
elseif contains(config.Channel, "rayleigh", "IgnoreCase", true)
    channel = comm.RayleighChannel;
elseif contains(config.Channel, "rician", "IgnoreCase", true)
    channel = comm.RicianChannel;
end
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
    if contains(config.Channel, "awgn", "IgnoreCase", true)
        channel.BitsPerSymbol = k;
    end
else
    error("Invalid Modulation Scheme");
end
% Calculate Spectral Efficiency
spectral_eff = mpsk_efficiency(config.Target_Data_Rate, M);
fprintf("Spectral Efficiency: %.2e bits/Hz\n", spectral_eff);
% Define RRC Pulse Shaping Matched Filters
txfilter = comm.RaisedCosineTransmitFilter("RolloffFactor", config.RRC_Filter_Props.RollOff, ...
    "FilterSpanInSymbols", config.RRC_Filter_Props.FilterSpanInSymbols, ...
    "OutputSamplesPerSymbol", config.RRC_Filter_Props.SamplesPerSymbol);
rxfilter = comm.RaisedCosineReceiveFilter("RolloffFactor", config.RRC_Filter_Props.RollOff, ...
    "FilterSpanInSymbols", config.RRC_Filter_Props.FilterSpanInSymbols, ...
    "InputSamplesPerSymbol", config.RRC_Filter_Props.SamplesPerSymbol, ...
    "DecimationFactor", config.RRC_Filter_Props.SamplesPerSymbol);
fvtool(txfilter, 'Analysis', 'impulse');
filterDelay = k * txfilter.FilterSpanInSymbols;
% Define BER and EVM Calculators
ber = comm.ErrorRate("ResetInputPort", true);
%Calculate Eb/No and SNR-------------------------
% https://www.dsprelated.com/showarticle/168.php?msclkid=dd85b998a7bb11ec8b9235e20eafce8c
Rs = config.Target_Data_Rate/k;
Rb = config.Target_Data_Rate;
Ps = minLB;
Pn = (-150:-80)';  % Estimated noise floor of background radiation
SNR = Ps - Pn;
No = Pn - 10*log10(config.Bandwidth);
Es = Ps - 10*log10(Rs);
Eb = Es - 10*log10(k);
EbNo = Eb - No;
minEbNo = config.Receiver_Sensitivity + config.Min_Link_Margin ...
    - 10*log10(Rs) - 10*log10(k) - No(end);
%-------------------------------------------------
% Initialize output vectors
berVec = zeros(length(Pn),3);
evmVec = zeros(length(Pn), 1);
errStats = zeros(1,3);
% Setup FEC
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
    bits_per_frame = 2^10;
    num_frames = (10/config.Max_BER) / bits_per_frame + 1;
end
%% Simulation
% Theoretical BER from Eb/No
[berTheory, serTheory] = berawgn(EbNo, 'psk', M, 'nondiff');
for i = 1:length(SNR)
    if contains(config.Channel, "awgn", "IgnoreCase", true)
        % Set EbNo for AWGN channel
        channel.EbNo = EbNo(i);
    end
    snr = SNR(i);
    % Define EVM Calculator
    evm = comm.EVM;
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
        evmStats = evm(modTx, modRx);
    end
    % Save stats and reset calculators
    berVec(i, :) = errStats;
    evmVec(i, :) = evmStats;
    errStats = ber(data_in, data_out, true);
end
%% Plot Figures
% Plot BER
berVec(berVec==0) = 1e-100;
berFigure = figure;
semilogy(EbNo,berVec(:,1));
hold on;
semilogy(EbNo,berTheory);
xline(minEbNo, '-', 'Minimum Eb/No');
yline(config.Max_BER, '-', 'Maximum BER');
ylim([1e-10, 1]);
title('BER vs Eb/No');
legend('Simulation','AWGN Theory','Location','Best');
xlabel('Eb/No (dB)');
ylabel('Bit Error Rate');
grid on;
hold off;
saveas(berFigure, "Figures/berFigure.png");
% Plot EVM
evmFigure = figure;
semilogy(EbNo,evmVec(:, 1));
hold on;
title('RMS EVM vs Eb/No');
xlabel('Eb/No (dB)');
ylabel('RMS EVM');
grid on;
hold off;
saveas(evmFigure, "Figures/evmFigure.png");
% Plot Link Margin
d = (maxR-1e6:maxR+1e6);
Lfs = fspl(d, lambda);
LB = config.Tx_Power + config.Ant_Gain * 2 - Lfs;
LM = LB - config.Receiver_Sensitivity;
LMFigure = figure;
plot(d,LM);
title('Link Margin vs Distance');
xline(maxR, '-', 'Maximum Distance');
yline(config.Min_Link_Margin, '-', 'Minimum Link Margin');
ylabel('Link Margin (dB)'); xlabel('Distance (m)');
saveas(LMFigure, "Figures/LMFigure.png");
