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
rng(SEED);  % Set random number generator seed
R = config.Target_Dist;  % Distance from transmitter to reciever
lambda = physconst('LightSpeed')/config.Freq;  % Wavelength
Lfs = fspl(R, lambda);  % Free-space path loss
% Calculate Link Margin and Link Budget
LB = config.Tx_Power + config.Ant_Gain * 2 - Lfs;  % Link Budget Calc
fprintf("Link Budget (%.2e m): %.2e dB\n", R, LB);
LM = LB - config.Receiver_Sensitivity;  % Link Margin Calc
fprintf("Link Margin (%.2e m): %.2e dB\n", R, LM);
% Recalculate LB/LM for max distance
maxLfs = config.Tx_Power + 2*config.Ant_Gain - config.Min_Link_Margin ...
    - config.Receiver_Sensitivity;
maxR = (lambda/(4*pi))*10^(maxLfs/20);
fprintf("Comm. Range: %.2e m\n", maxR);
fprintf("Min. Number of Nodes: %d\n", MAX_DIST_TO_MARS/maxR);
minLB = config.Tx_Power + config.Ant_Gain * 2 - maxLfs;
if contains(config.Mod_Scheme, "QPSK", 'IgnoreCase', true)
    M = 4;  % Modulation Alphabet
    k = log2(M);  % Bits per symbol
    % Define QPSK modulator
    modulator = comm.QPSKModulator('BitInput',true);
    % Define QPSK demodulator
    demodulator = comm.QPSKDemodulator('BitOutput', true);
    isQPSK = true;
    % Initialize Channel Model
    channel = comm.AWGNChannel("BitsPerSymbol", k);
else
    error("Invalid Modulation Scheme");
end
spectral_eff = mpsk_efficiency(config.Target_Data_Rate, M);
fprintf("Spectral Efficiency: %.2e bits/Hz\n", spectral_eff);
% Define BER and EVM Calculators
ber = comm.ErrorRate("ResetInputPort", true);
ser = comm.ErrorRate("ResetInputPort", true);
%-------------------------
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
%-------------------------
% Initialize output vectors
berVec = zeros(length(Pn),3);
serVec = zeros(length(Pn),3);
evmVec = zeros(length(Pn), 1);
errStats = zeros(1,3);
isLDPC = false;
fprintf("FEC:\n");
disp(config.FEC);
if contains(config.FEC.Method, "LDPC", "IgnoreCase", true)
    % Valid Code Rates: 1/4, 1/3, 2/5, 1/2, 3/5,
    % 2/3, 3/4, 4/5, 5/6, 8/9, or 9/10
    codeRate = eval(config.FEC.Code_Rate);
    H = dvbs2ldpc(codeRate);
    maxnumiter = 50;
    cfgLDPCEnc = ldpcEncoderConfig(H);
    cfgLDPCDec = ldpcDecoderConfig(cfgLDPCEnc);
    bits_per_frame = cfgLDPCEnc.NumInformationBits;
    num_frames = (10/config.Max_BER) / bits_per_frame + 1;
    isLDPC = true;
else
    % Default to 1 KB frames
    bits_per_frame = 2^10;
    num_frames = (10/config.Max_BER) / bits_per_frame + 1;
end
%% Simulation
[berTheory, serTheory] = berawgn(EbNo, 'psk', M, 'nondiff');  % Theoretical BER from Eb/No
for i = 1:length(SNR)
    channel.EbNo = EbNo(i);
    snr = SNR(i);  % SNR
    evm = comm.EVM;
    if isLDPC
        demodulator = comm.QPSKDemodulator('BitOutput',true, ...
            'DecisionMethod','Approximate log-likelihood ratio', ...
            'Variance', 1/10^(snr/10));
    end
    for counter = 1:num_frames
        if isLDPC
            data_in = randi([0 1], bits_per_frame, 1, "int8");
            encodedData = ldpcEncode(data_in, cfgLDPCEnc);
        else
            data_in = randi([0 1], bits_per_frame, 1);
            encodedData = data_in;
        end
        modTx = modulator(encodedData);
        txSig = modTx;
        rxSig = channel(txSig);
        modRx = rxSig;
        demodRx = demodulator(modRx);
        if isLDPC
            data_out = ldpcDecode(demodRx, cfgLDPCDec, maxnumiter);
        else
            data_out = demodRx;
        end
        errStats = ber(data_in, data_out, false);
        serStats = ser(modTx, modRx, false);
        evmStats = evm(modTx, modRx);
    end
    berVec(i, :) = errStats;
    serVec(i, :) = serStats;
    evmVec(i, :) = evmStats;
    errStats = ber(data_in, data_out, true);
    serStats = ser(modTx, modRx, true);
end
%% Plot Figures
% Plot BER
berVec(berVec==0) = 1e-100;
figure;
semilogy(EbNo,berVec(:,1));
hold on;
semilogy(EbNo,berTheory);
xline(minEbNo, '-', 'Minimum Eb/No');
yline(config.Max_BER, '-', 'Maximum BER');
ylim([1e-10, 1]);
title('BER vs Eb/No');
legend('Simulation','Theory','Location','Best');
xlabel('Eb/No (dB)');
ylabel('Bit Error Rate');
grid on;
hold off;
% Plot SER
figure;
semilogy(EbNo,serVec(:,1));
hold on;
semilogy(EbNo, serTheory);
title('SER vs Eb/No');
legend('Simulation','Theory','Location','Best');
xlabel('Eb/No (dB)');
ylabel('Symbol Error Rate');
ylim([1e-10, 1]);
yline(config.Max_SER, '-', 'Maximum SER');
grid on;
hold off;
% Plot EVM
figure;
semilogy(EbNo,evmVec(:, 1));
hold on;
title('RMS EVM vs Eb/No');
xlabel('Eb/No (dB)');
ylabel('RMS EVM');
grid on;
hold off;
% Plot Link Margin
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
