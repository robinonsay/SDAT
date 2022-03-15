function [dataOut, txSig, rxSig] = sendQPSK(channel, dataIn)
%SENDQPSK Summary of this function goes here
%   Detailed explanation goes here
M = 4;  % Modulation Alphabet
k = log2(M);  % Bits per symbol
qpskMod = comm.QPSKModulator("BitInput",true);  % Input is Binary
qpskDemod = comm.QPSKDemodulator("BitOutput",true);  % Output is Binary
release(channel);
channel.BitsPerSymbol = k;  % k bits per symbol
txSig = qpskMod(dataIn);
rxSig = channel(txSig);
dataOut = qpskDemod(rxSig);
end

