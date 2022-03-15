%% Initialize Constants
RANDOM_SEED = 3165;
NUM_BITS = 1e6;  % Maximum number of bits transmitted
%% Import Config
config_name = input("Config File Name? ", "s");
if isempty(config_name)
    config_name = "default_config.json";
end
fid = fopen(config_name);
config_json = char(fread(fid, inf)');
fclose(fid);
config = jsondecode(config_json);
%% Setup Channel
rng(RANDOM_SEED);
channel = comm.AWGNChannel("NoiseMethod", "Signal to noise ratio (Eb/No)", ...
    "EbNo", config.EbNo, ...
    "SignalPower", config.Signal_Pwr, ...
    "SamplesPerSymbol", config.Samples_Per_Symbol);
errRate = comm.ErrorRate('ResetInputPort',true);
dataIn = randi([0,1], NUM_BITS, 1);
%% Send data over noisy channel
if config.Mod_Scheme == "QPSK"  % If modulation scheme is QPSK
    M = 4;  % Modulation Alphabet
    berTheory = berawgn(config.EbNo, "psk", M, "nondiff");
    [dataOut, txSig, rxSig] = sendQPSK(channel, dataIn);
else
    disp("Invalid Modulation Scheme")
    quit(-1);
end
errStats = errRate(dataIn, dataOut, 0);
BER = errStats(1);
errCount = errStats(2);
scatterplot(txSig);
scatterplot(rxSig);
fprintf("EbNo:\t\t%d\n", config.EbNo);
fprintf("BER:\t\t%d\n", BER);
fprintf("Error Count:\t%d\n", errCount);
