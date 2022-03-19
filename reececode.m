clear, clc
%Data Rate
%data rate = 2 * bandwidth *log2 (M) M=4 (QPSK);
% for noisy channel 

%Shannon capacity = bandwidth x log2 (1 + SNR)

%Theoretical highest data rate for a noisy channel
%This gives capacity not data rate
SNR=14; 
Bandwidth=50*10^6; %Hz
Shannon = Bandwidth*log2(1+SNR); %gives bps
Nyquist = 2*Bandwidth*log2(4);
if Nyquist < Shannon
    MaxDataRate=Nyquist;
else
    MaxDatarate=Shannon;
end
%Error Vector Magnitude (EVM)

evm = lteEVM(dataout,datain); %dataout is input values, datain is reference signal