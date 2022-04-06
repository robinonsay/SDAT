%% Constants
SEED = 3165;
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
rng(SEED);  % Set random number generator seed
R = config.Target_Dist;  % Distance from transmitter to reciever
lambda = physconst('LightSpeed')/config.Freq;  % Wavelength
Lfs = fspl(R, lambda);  % Free-space path loss
% Calculate Link Margin and Link Budget
LB = config.Tx_Power + config.Ant_Gain * 2 - Lfs;  % Link Budget Calc
fprintf("Link Budget (%.2e m): %.2e dB\n", R, LB);
LM = LB - config.Receiver_Sensitivity;  % Link Margin Calc
fprintf("Link Margin (%.2e m): %.2e dB\n", R, LM);
% Initialize Channel Model
channel = comm.AWGNChannel("VarianceSource", "Input port", ...
    "NoiseMethod", "Variance");
% Define Error Vector Magnitude Calculator
evm = comm.EVM;
if contains(config.Mod_Scheme, "QPSK", 'IgnoreCase', true)
    M = 4;  % Modulation Alphabet
    k = log2(M);  % Bits per symbol
    % Define QPSK modulator
    modulator = comm.QPSKModulator('BitInput',true);
    % Define QPSK demodulator
    demodulator = comm.QPSKDemodulator('BitOutput',true);
    fprintf("Spectral Efficiency: %d bits/Hz\n", ...
        mpsk_efficiency(config.Target_Data_Rate, M));
else
    error("Invalid Modulation Scheme");
end
% Based CCSDS RRC filter (Matt)
txfilter = comm.RaisedCosineTransmitFilter("RolloffFactor", 0.35, ...
    "FilterSpanInSymbols", 10, "OutputSamplesPerSymbol", 10);
rxfilter = comm.RaisedCosineReceiveFilter("RolloffFactor", 0.35, ...
    "FilterSpanInSymbols", 10, "InputSamplesPerSymbol", 10, ...
    "DecimationFactor", 10);
%-------------------------
% https://www.dsprelated.com/showarticle/168.php?msclkid=dd85b998a7bb11ec8b9235e20eafce8c
Rs = config.Target_Data_Rate/k;
Rb = config.Target_Data_Rate;
Ps = LB;
Pn = (config.Receiver_Sensitivity:-50)';  % Estimated noise floor of background radiation
SNR = Ps - Pn;
No = Pn - 10*log10(config.Bandwidth);
Es = Ps - 10*log10(Rs);
Eb = Es - 10*log10(k);
EbNo = Eb - No;
minEbNo = config.Receiver_Sensitivity + config.Min_Link_Margin ...
    - 10*log10(Rs) - 10*log10(k) - No(end);
%-------------------------
% Initialize output vectors
berVec = zeros(length(Pn),1);
serVec = zeros(length(Pn),1);
evmVec = zeros(length(Pn), 1);
isLDPC = false;
if contains(config.FEC.Method, "LDPC", "IgnoreCase", true)
    fprintf("FEC Method: LDPC\nLDPC Config:\n");
    disp(config.FEC);
    % Valid Code Rates: 1/4, 1/3, 2/5, 1/2, 3/5,
    % 2/3, 3/4, 4/5, 5/6, 8/9, or 9/10
    codeRate = eval(config.FEC.Code_Rate);
    H = dvbs2ldpc(codeRate);
    maxnumiter = 10;
    cfgLDPCEnc = ldpcEncoderConfig(H);
    cfgLDPCDec = ldpcDecoderConfig(cfgLDPCEnc);
    infoBits = randi([0 1], cfgLDPCEnc.NumInformationBits, 1, "int8");  % Uniform Distribution
    dataIn = ldpcEncode(infoBits, cfgLDPCEnc);
    isLDPC = true;
else
    infoBits = randi([0 1], 2^20, 1, "int8");
    dataIn = infoBits;
end
%% Simulation
berTheory = berawgn(EbNo, 'psk', M, 'nondiff');  % Theoretical BER from Eb/No
for i = 1:length(SNR)
    snr = SNR(i);  % SNR
    modTx = modulator(dataIn);  % QPSK modulated data
    powerDB = 10*log10(var(modTx));  % Power of signal
    noiseVar = 10.^(0.1*(powerDB-snr));  % Noise Variance of signal
    txSig = txfilter(modTx); % Pulse Shaping Filter
%     txSig = modTx;
    rxSig = channel(txSig, noiseVar);  % Send signal over noisy channel
%     rxSig = txSig;
    modRx = rxfilter(rxSig);  % Pulse Shaping Filter
%     modRx = rxSig;
    dataOut = demodulator(modRx);  % Demodulate signal
    if isLDPC
        rxInfoBits = ldpcDecode(dataOut, cfgLDPCDec, maxnumiter);
    else
        rxInfoBits = dataOut;
    end
    % Calculate Outputs
    [berrNum, ber] = biterr(infoBits, rxInfoBits);
    berVec(i) = ber;
    [serrNum, ser] = symerr(modTx, modRx);
    serVec(i) = ser;
    evmVec(i) = evm(modTx, modRx);
end
%% Plot Figures
% Plot BER
figure;
semilogy(EbNo,berVec(:,1));
hold on;
semilogy(EbNo,berTheory);
xline(minEbNo, '-', 'Minimum Eb/No');
yline(config.Max_BER, '-', 'Maximum BER');
ylim([1e-10, 1e0]);
title('BER vs Eb/No');
legend('Simulation','Theory','Location','Best');
xlabel('Eb/No (dB)');
ylabel('Bit Error Rate');
grid on;
hold off;
% Plot SER
figure;
semilogy(EbNo,serVec);
hold on;
title('SER vs Eb/No');
xlabel('Eb/No (dB)');
ylabel('Symbol Error Rate');
ylim([1e-5, 1e5]);
yline(config.Max_SER, '-', 'Maximum SER');
grid on;
hold off;
% Plot EVM
figure;
semilogy(EbNo,evmVec);
hold on;
title('RMS EVM vs Eb/No');
xlabel('Eb/No (dB)');
ylabel('RMS EVM');
grid on;
hold off;
% Plot Link Margin
maxLfs = config.Tx_Power + 2*config.Ant_Gain - config.Min_Link_Margin ...
    - config.Receiver_Sensitivity;
maxR = (lambda/(4*pi))*10^(maxLfs/20);
d = (maxR-1e6:maxR+1e6);
Lfs = fspl(d, lambda);
LB = config.Tx_Power + config.Ant_Gain * 2 - Lfs;
LM = LB - config.Receiver_Sensitivity;
figure;
plot(d,LM);
title('Link Margin vs Distance');
xline(maxR, '-', 'Maximum Distance');
yline(config.Min_Link_Margin, '-', 'Minimum Link Margin');
ylabel('Link Margin (dB)'); xlabel('Distance (m)');
fprintf("Comm. Range: %.2e m\n", maxR);