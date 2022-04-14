function c = mpsk_efficiency(bw, snr)
    c = bw * log2(1+snr);
end

