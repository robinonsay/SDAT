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
tx = txsite("CoordinateSystem", "cartesian", "AntennaPosition", [0;0;0], ...
    "TransmitterFrequency", config.Freq, ...
    "TransmitterPower", config.Tx_Power + config.Ant_Gain);
rx = rxsite("CoordinateSystem", "cartesian", "AntennaPosition", [config.Target_Distance;0;0], ...
    "ReceiverSensitivity", config.Receiver_Sensitivity);
signalStrength = sigstrength(rx, tx, "freespace");
fprintf("Signal Strength at Receiver: %d dBm\n", signalStrength);
noiseFloorVec = (-120:0.5:-90)';
minEbNo = config.Receiver_Sensitivity - noiseFloorVec(end) - ...
    10*log10(config.Target_Data_Rate/config.Bandwidth);
snrVec = signalStrength - noiseFloorVec;
EbNoVec = snrVec - 10*log10(config.Target_Data_Rate/config.Bandwidth);
channel = comm.AWGNChannel("VarianceSource", "Input port", ...
    "NoiseMethod", "Variance");
bitErrRate = comm.ErrorRate("ResetInputPort", true);
% snrVec = EbNoVec + 10*log10(config.Target_Data_Rate/config.Bandwidth);
berVec = zeros(length(noiseFloorVec),3);
serVec = zeros(length(noiseFloorVec),2);
dataIn = randi([0,1], 1e6, 1);
%% Simulation
if contains(config.Mod_Scheme, "QPSK")
    M = 4;
    k = log2(M);
    qpskMod = comm.QPSKModulator('BitInput',true);
    qpskDemod = comm.QPSKDemodulator('BitOutput',true);
    txfilter = comm.RaisedCosineTransmitFilter;
    rxfilter = comm.RaisedCosineReceiveFilter;
    for i = 1:length(noiseFloorVec)
        snr = snrVec(i);
        qpskTx = qpskMod(dataIn);
        txSig = txfilter(qpskTx);
%         txSig = qpskTx;
        powerDB = 10*log10(var(txSig));
        noiseVar = 10.^(0.1*(powerDB-snr));
        rxSig = channel(txSig, noiseVar);
        qpskRx = rxfilter(rxSig);
%         qpskRx = rxSig;
        dataOut = qpskDemod(qpskRx);
        berVec(i,:) = bitErrRate(dataIn, dataOut, 1);
        serVec(i,:) = symerr(qpskTx, qpskRx);
    end
    berTheory = berawgn(EbNoVec, 'psk', M, 'nondiff');
end
figure
semilogy(EbNoVec,berVec(:,1),'*')
hold on
semilogy(EbNoVec,berTheory)
xline(minEbNo);
ylim([1e-1, 1e1]);
title('BER');
legend('Simulation','Theory','Location','Best')
xlabel('Eb/No (dB)')
ylabel('Bit Error Rate')
grid on
hold off

figure
semilogy(EbNoVec,serVec(:,2),'*')
hold on
title('SER');
xlabel('Eb/No (dB)')
ylabel('Bit Error Rate')
grid on
hold off
