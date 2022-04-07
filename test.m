M = 4;  % Modulation Alphabet
k = log2(M);  % Bits per symbol
% Define QPSK modulator
modulator = comm.QPSKModulator('BitInput',true);
% Define QPSK demodulator
demodulator = comm.QPSKDemodulator('BitOutput', true);
txfilter = comm.RaisedCosineTransmitFilter;
rxfilter = comm.RaisedCosineReceiveFilter;
filterDelay = k * txfilter.FilterSpanInSymbols;
% data_in = [0 0 0 1 1 0 1 1]';
data_in = randi([0 1], 100, 1);
encoded_data = [data_in', zeros(filterDelay, 1)']';
modTx = modulator(encoded_data);
% scatterplot(modTx);
txSig = txfilter(modTx);
%         txSig = modTx;
rxSig = txSig;
%         modRx = rxSig;
modRx = rxfilter(rxSig);
% scatterplot(modRx);
data_out = demodulator(modRx);
delay = dsp.Delay(filterDelay);
delay_out = delay(encoded_data);
data_out(1:filterDelay) = [];
delay_out(1:filterDelay) = [];
comp = delay_out == data_out;
comp_fix = data_out == data_in;