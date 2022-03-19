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
LB = config.Tx_Power + config.Ant_Gain * 2 - Lfs;  % Link Budget Calc
fprintf("Link Budget (%.2e m): %.2e dB\n", R, LB);
LM = LB - config.Receiver_Sensitivity;  % Link Margin Calc
fprintf("Link Margin (%.2e m): %.2e dB\n", R, LM);
noiseFloorVec = (-200:-50)';  % Estimated noise floor of background radiation
minEbNo = config.Receiver_Sensitivity + config.Min_Link_Margin - noiseFloorVec(end) - ...
    10*log10(config.Target_Data_Rate/config.Bandwidth);  % Minimum EbNo for reciever
snrVec = LB - noiseFloorVec;  % Signal-to-Noise Ratio vector
EbNoVec = snrVec - 10*log10(config.Target_Data_Rate/config.Bandwidth);  % Eb/No from SNR
channel = comm.AWGNChannel("VarianceSource", "Input port", ...
    "NoiseMethod", "Variance");  % Define noisy channel
% Research channel models (using best-case awgn
thNoise = comm.ThermalNoise;  % Define Thermal Noise
evm = comm.EVM;  % Define Error Vector Magnitude Calculator
% Initialize output vectors
berVec = zeros(length(snrVec),1);
serVec = zeros(length(snrVec),1);
evmVec = zeros(length(snrVec), 1);
dataIn = randi([0,1], 1e6, 1);  % Bernoulii Distribution of random bits
%% Simulation
if contains(config.Mod_Scheme, "QPSK")
    M = 4;  % Modulation Alphabet
    k = log2(M);  % Bits per symbol
    qpskMod = comm.QPSKModulator('BitInput',true);  % Define QPSK modulator
    qpskDemod = comm.QPSKDemodulator('BitOutput',true);  % Define QPSK demodulator
%     txfilter = comm.RaisedCosineTransmitFilter("RolloffFactor", 0.35, ...
%         "FilterSpanInSymbols", 10, "OutputSamplesPerSymbol", 10);
%     rxfilter = comm.RaisedCosineReceiveFilter("RolloffFactor", 0.35, ...
%         "FilterSpanInSymbols", 10, "InputSamplesPerSymbol", 10, ...
%         "DecimationFactor", 10);
    berTheory = berawgn(EbNoVec, 'psk', M, 'nondiff');  % Theoretical BER from Eb/No
    for i = 1:length(snrVec)
        snr = snrVec(i);  % SNR
        qpskTx = qpskMod(dataIn);  % QPSK modulated data
        powerDB = 10*log10(var(qpskTx));  % Power of signal
        noiseVar = 10.^(0.1*(powerDB-snr));  % Noise Variance of signal
%         txSig = txfilter(qpskTx);
        txSig = qpskTx;
        rxSig = channel(txSig, noiseVar);  % Send signal over noisy channel with added thermal noise
%         qpskRx = rxfilter(rxSig);
        qpskRx = rxSig;
        dataOut = qpskDemod(qpskRx);  % Demodulate signal
        % Calculate Outputs
        [berrNum, ber] = biterr(dataIn, dataOut);
        berVec(i) = ber;
        [serrNum, ser] = symerr(qpskTx, qpskRx);
        serVec(i) = ser;
        evmVec(i) = evm(txSig, rxSig);
    end
end

%% Plot Figures
% Plot BER
berVec(berVec==0) = 1e-10;
figure;
semilogy(EbNoVec,berVec(:,1));
hold on;
semilogy(EbNoVec,berTheory);
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
semilogy(EbNoVec,serVec);
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
semilogy(EbNoVec,evmVec);
hold on;
title('RMS EVM vs Eb/No');
xlabel('Eb/No (dB)');
ylabel('RMS EVM');
grid on;
hold off;
% Plot Link Margin
d = (1e6:2e6);
Lfs = fspl(d, lambda);
LB = config.Tx_Power + config.Ant_Gain * 2 - Lfs;
LM = LB - config.Receiver_Sensitivity;
commRange = interp1((LM-config.Min_Link_Margin), d, 0);
figure;
plot(d,LM);
title('Link Margin vs Distance');
xline(commRange, '-', 'Maximum Distance');
yline(config.Min_Link_Margin, '-', 'Minimum Link Margin');
ylabel('Link Margin (dB)'); xlabel('Distance (km)');
fprintf("Comm. Range: %.2e m\n", commRange);