function sample = FPAS_Sample
global FPAS PARAMS;

if nargin<1
    method = 0;
end

switch FPAS.sample_method
    
    %% Really go to the hardware
    case 0
        
        %% start the task
        DAQmxStartTask(lib,FPAS.hTask);

        %% read 
        timeout = 1;
        fillMode = DAQmx_Val_GroupByChannel; % Group by Channel
        %fillMode = DAQmx_Val_GroupByScanNumber; % I think this doesn't matter when only 1 channel

        [portdata,sampsPerChanRead] = DAQmxReadDigitalU32(lib,hTask,numchan,sampsPerChan,timeout,fillMode,bufSizeInSamps);

        %portdata

        %% stop
        DAQmxStopTask(lib,hTask);

        %% clear
        DAQmxClearTask(lib,hTask);

        %% swizzle data (could be optimized for memory and speed)
        nPerBoard = 32; %has to do with the number of channels on the boards going to the FIFO

        ind = [];
        for ii = 1:ceil(nChan/nPerBoard)
          ind = [ind,[1:2:15 2:2:16; 17:2:31 18:2:32]+(ii-1)*32];
        end
        ind = ind(:);

        %how many channels do you need to keep to unravel all the data correctly
        maxInd = ceil(nChan/nPerBoard)*nPerBoard; 

        %throw away first point because it is empty
        hm = portdata(2:end);

        %throw away as many points as we can without losing information
        hm = reshape(hm,FPAS.nMaxChan/2,nShots);
        hm = hm(1:maxInd/2,:);

        %flatten again
        hm = hm(:); 

        %convert each 32bit number to two 16bit numbers
        hmm = typecast(hm,'uint16');
        hmm = reshape(hmm,maxInd,nShots);

        %use ind to sort the data
        IND = repmat(ind,1,nShots); %this only needs to happen once per scan
        data = zeros(size(IND)); %initialize size of array (once per scan)
        data = hmm(IND);

        %% extract array part and ext channels part
        sample.data.pixels = double(data(1:nPixels,:)); %the first 64 rows
        sample.data.external = double(data((nPixels+1):(nPixels+nExtInputs),:))./13107; %the last 16 rows divided by some magic number I don't understand to make volts?

    %% Uniform Distribution
    case 1
        sample.data.pixels = random('uniform', 0.0, 5.0, 64, PARAMS.nShots);
        sample.data.external = random('uniform', 0.0, 5.0, 16, PARAMS.nShots);

    %% Simulate offset sech^2 peaks with Gaussian noise
    case 2
        for ii=1:32
            sample.data.pixels(ii, :)    = abs(sech((ii-14)/6)^2 + random('Normal', 0, .2, 1, PARAMS.nShots));
            sample.data.pixels(ii+32,:) = abs(sech((ii-18)/6)^2 + random('Normal', 0, .2, 1, PARAMS.nShots));
        end
        sample.data.external = random('uniform', 0.0, 5.0, 16, PARAMS.nShots);
        
    %% Simulate matching sech^2 peaks with Gaussian noise on sample to test noise calculations
    case 3
        for ii=1:32
            sample.data.pixels(ii+32,:) = repmat(sech((ii-16)/12)^2 + 0.1, 1, PARAMS.nShots);
            sample.data.pixels(ii,:)    = sample.data.pixels(ii+32,:).*(1+random('Normal', 0.0, 0.00001, 1, PARAMS.nShots));
        end
        sample.data.external = random('uniform', 0.0, 5.0, 16, PARAMS.nShots);
        
end       

%% Final processing for this sample
sample.mean.pixels = mean(sample.data.pixels, 2);
sample.mean.external = mean(sample.data.external, 2);

sample.mOD = log10(sample.data.pixels([33:64],:)./sample.data.pixels([1:32],:))*1000;
sample.noise = std(sample.mOD, 1, 2);
sample.mOD = mean(sample.mOD, 2);
