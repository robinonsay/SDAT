%% Initialize Constants
MAX_BIT_ERRORS = 100;  % Maximum number of bit errors
MAX_NUM_BITS = 1e7;  % Maximum number of bits transmitted
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
channel = comm.AWGNChannel("NoiseMethod", "Signal to noise ratio (Eb/No)", ...
    "EbNo", config.Eb_N0, ...
    "SignalPower", config.Signal_Pwr, ...
    "SamplesPerSymbol", config.Samples_Per_Symbol);
%% Send data over noisy channel
if config.Mod_Scheme == "QPSK"  % If modulation scheme is QPSK
    M = 4;  % Modulation Alphabet
    k = log2(M);  % Bits per symbol
    qpskMod = comm.QPSKModulator("BitInput",true);  % Input is Binary
    qpskDemod = comm.QPSKDemodulator("BitOutput",true);  % Output is Binary
    channel.BitsPerSymbol = k;  % k bits per symbol
else
    disp("Invalid Modulation Scheme")
end
