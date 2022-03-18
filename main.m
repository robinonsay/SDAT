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
rng(SEED);
R = config.Target_Dist;
lambda = physconst('LightSpeed')/config.Freq;
Lfs = fspl(R, lambda);
LB = config.Tx_Power + config.Ant_Gain * 2 - Lfs;
fprintf("Link Budget (%.2e m): %.2e dB\n", R, LB);
LM = LB - config.Receiver_Sensitivity;
fprintf("Link Margin (%.2e m): %.2e dB\n", R, LM);
noiseFloorVec = (-200:-50)';
minEbNo = config.Receiver_Sensitivity + config.Min_Link_Margin - noiseFloorVec(end) - ...
    10*log10(config.Target_Data_Rate/config.Bandwidth);
snrVec = LB - noiseFloorVec;
EbNoVec = snrVec - 10*log10(config.Target_Data_Rate/config.Bandwidth);
channel = comm.AWGNChannel("VarianceSource", "Input port", ...
    "NoiseMethod", "Variance");
thNoise = comm.ThermalNoise;
bitErrRate = comm.ErrorRate("ResetInputPort", true);
evm = comm.EVM;
berVec = zeros(length(snrVec),3);
serVec = zeros(length(snrVec),1);
evmVec = zeros(length(snrVec), 1);
dataIn = randi([0,1], 1e6, 1);
%% Simulation
if contains(config.Mod_Scheme, "QPSK")
    M = 4;
    k = log2(M);
    qpskMod = comm.QPSKModulator('BitInput',true);
    qpskDemod = comm.QPSKDemodulator('BitOutput',true);
    txfilter = comm.RaisedCosineTransmitFilter("RolloffFactor", 0.35, ...
        "FilterSpanInSymbols", 10, "OutputSamplesPerSymbol", 10);
    rxfilter = comm.RaisedCosineReceiveFilter("RolloffFactor", 0.35, ...
        "FilterSpanInSymbols", 10, "InputSamplesPerSymbol", 10, ...
        "DecimationFactor", 10);
%     berTheory = berawgn(EbNoVec, 'psk', M, 'diff');
    for i = 1:length(snrVec)
        snr = snrVec(i);
        qpskTx = qpskMod(dataIn);
%         txSig = txfilter(qpskTx);
        txSig = qpskTx;
        powerDB = 10*log10(var(txSig));
        noiseVar = 10.^(0.1*(powerDB-snr));
        rxSig = thNoise(channel(txSig, noiseVar));
%         qpskRx = rxfilter(rxSig);
        qpskRx = rxSig;
        dataOut = qpskDemod(qpskRx);
        berVec(i,:) = bitErrRate(dataIn, dataOut, 1);
        [serrNum, ser] = symerr(qpskTx, qpskRx);
        serVec(i) = ser;
        evmVec(i) = evm(txSig, rxSig);
    end
end

berVec(berVec==0) = 1e-10;
figure
semilogy(EbNoVec,berVec(:,1))
hold on
% semilogy(EbNoVec,berTheory)
xline(minEbNo, '-', 'Minimum Eb/No');
yline(config.Max_BER, '-', 'Maximum BER');
ylim([1e-10, 1e0]);
title('BER vs Eb/No');
% legend('Simulation','Theory','Location','Best')
xlabel('Eb/No (dB)')
ylabel('Bit Error Rate')
grid on
hold off

figure
semilogy(EbNoVec,serVec,'*')
hold on
title('SER vs Eb/No');
xlabel('Eb/No (dB)');
ylabel('Symbol Error Rate');
yline(config.Max_SER, '-', 'Maximum SER');
grid on
hold off

figure
semilogy(EbNoVec,evmVec)
hold on
title('RMS EVM vs Eb/No');
xlabel('Eb/No (dB)');
ylabel('RMS EVM');
grid on
hold off

%Showing a graph of the Distance v Link Margin with the Link Margin Minimum
%added in as a horizontal line
d = (1e6:2e6);
Lfs = fspl(d, lambda);
LB = config.Tx_Power + config.Ant_Gain * 2 - Lfs;
LM = LB - config.Receiver_Sensitivity;
commRange = interp1((LM-config.Min_Link_Margin), d, 0);
figure
plot(d,LM);
xline(commRange, '-', 'Maximum Distance');
yline(config.Min_Link_Margin, '-', 'Minimum Link Margin')
ylabel('Link Margin (dB)'); xlabel('Distance (km)')
fprintf("Comm. Range: %.2e m\n", commRange);