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
channel = comm.AWGNChannel("VarianceSource", "Input port", ...
    "NoiseMethod", "Variance");
errorRate = comm.ErrorRate("ResetInputPort", true);
EbNoVec = (-45:-30)';
snrVec = EbNoVec + 10*log10(config.Target_Data_Rate/config.Bandwidth);
berVec = zeros(length(EbNoVec),3);
dataIn = randi([0,1], 1e6, 1);
%% Simulation
if contains(config.Mod_Scheme, "QPSK")
    M = 4;
    k = log2(M);
    qpskMod = comm.QPSKModulator('BitInput',true);
    qpskDemod = comm.QPSKDemodulator('BitOutput',true);
    for i = 1:length(EbNoVec)
        snr = snrVec(i);
        txSig = qpskMod(dataIn);
        powerDB = 10*log10(var(txSig));
        noiseVar = 10.^(0.1*(powerDB-snr));
        rxSig = channel(txSig, noiseVar);
        dataOut = qpskDemod(rxSig);
        berVec(i,:) = errorRate(dataIn, dataOut, 1);
    end
    berTheory = berawgn(EbNoVec,'psk',M,'nondiff');
end
figure
semilogy(EbNoVec,berVec(:,1),'*')
hold on
semilogy(EbNoVec,berTheory)
legend('Simulation','Theory','Location','Best')
xlabel('Eb/No (dB)')
ylabel('Bit Error Rate')
grid on
hold off
