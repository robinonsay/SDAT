minDataRate= 1.6e6;
targetDataRate = 20e6;
Bandwidth = 50e6;
Power = 33;
disp("Spectral Efficiency: ");
disp(mySpectral(minDataRate, targetDataRate, Bandwidth) + '%');
disp("Power Efficiency: ");
disp(myPower(minDataRate, targetDataRate, Bandwidth, Power)+ '%');
function SpectralEfficiency = mySpectral(minDataRate, targetDataRate, Bandwidth)
    rate = minDataRate:1:targetDataRate;
    Spectrum = sum(rate);
    SpectralEfficiency = Spectrum/Bandwidth;
    SpectralEfficiency = SpectralEfficiency / 1e5;
end

function PowerEfficiency = myPower(minDataRate, targetDataRate,Bandwidth, Power)
    rate = minDataRate:1:targetDataRate;
    PowerEfficiency = (sum(rate)/Bandwidth)/Power*100;
    PowerEfficiency = PowerEfficiency / 1e6;
end

