function n = mpsk_efficiency(rb, M)
% function inputs:
% rb = bit rate
% M = no. of symbols of M-ary PSK
% function output :
% n = spectral efficiency in bits/Hz
    if nargin ~= 2
    error('Number of input arguments must be 2');
    end
    if M<2 || mod(log2(M),1)~=0
    error('M must be a positive integral power of 2');
    end
    bw = 2rb/log2(M);
    bweff = rb/bw;
    n = 2rb*bweff;
end

