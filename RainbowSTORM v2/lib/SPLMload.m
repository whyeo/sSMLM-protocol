function data = SPLMload(FileName,format,structure)
%load SPLM image
%   format - is the format of the raw stacked image  
%       'spe' - EMpro camera
%       'nd2' - Andor Ixon camera
%       'tiff' - stacked Tiff file
%       'dat' - ascii data
%   structure  
%       'uint16'
%       'double'

if nargin<3 | isempty(structure)
    structure = 'uint16';
end

switch format
    case 'spe' 
        readerobj = SpeReader(FileName);
        data = read(readerobj);
        if structure=='double'
            data=double(squeeze(data));
        end
    case {'tiff'}
        InfoImage=imfinfo(FileName);
        mImage=InfoImage(1).Width;
        nImage=InfoImage(1).Height;
        NumberImages=length(InfoImage);
        data=zeros(nImage,mImage,NumberImages,'uint16');

        TifLink = Tiff(FileName, 'r');
        for i=1:NumberImages
           TifLink.setDirectory(i);
           data(:,:,i)=TifLink.read();
        end
        TifLink.close();
        if structure=='double'
            data=double(data);
        end
    case 'nd2' 
        data = bfOpen3DVolume(FileName);
        if size(data) == [1,4]
            data = data{1}{1};
            if structure=='double'
                data=double(data);
            end
        else
            error('error');
        end

    case 'dat'
        fid = fopen(FileName, 'r', 'ieee-le');
        if fid==-1
            error('cannot open raw data');
        end
        [data, cnt] = fread(fid, 'uint16');
        fclose(fid);
        if structure=='double'
            data=double(data);
        end
    otherwise
        warning('Unknown format.')
end

return