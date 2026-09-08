clc; clear all; close all;

inmg = 0;

% Ruta base para recortes del tamaño máximo
basePath = 'C:\Users\lilia\OneDrive\Desktop\PORGRADO\TESIS\BreastCancer\Recortes\';

% (Opcional) Ruta base para guardar también las imágenes 32x32 por clase
basePath32 = 'C:\Users\lilia\OneDrive\Desktop\PORGRADO\TESIS\BreastCancer\Recortes_CNN_32x32\';

% Ruta base para guardar las máscaras completas I4F por clase
basePathI4F_full = 'C:\Users\lilia\OneDrive\Desktop\PORGRADO\TESIS\BreastCancer\I4F_Completas\';

% Ruta base para guardar los recortes (bounding box) de I4F por clase (32x32)
basePathI4F_crop = 'C:\Users\lilia\OneDrive\Desktop\PORGRADO\TESIS\BreastCancer\I4F_Recortes_32x32\';

maxSide  = 0;      % para buscar el tamaño máximo de bounding box
contClase1 = 0;    % contador imágenes NO TUMOR (clase 1)
contClase2 = 0;    % contador imágenes TUMOR (clase 2)



% ==========================================================
%   PARTE 1: CÁLCULO DEL TAMAÑO CUADRADO MÁXIMO (maxSide)
for img = 1:129
    pathGT  = ['C:\Users\lilia\OneDrive\Desktop\PORGRADO\TESIS\BreastCancer\seg_gris\GT\Entrada\', num2str(img) ,'GTM.bmp'];
    pathRGB = ['C:\Users\lilia\OneDrive\Desktop\PORGRADO\TESIS\BreastCancer\seg_gris\GT\Entrada\', num2str(img) ,'rgb_mask.bmp'];

    GT   = imread(pathGT);
    Irgb = imread(pathRGB);

    GT    = logical(GT(:,:,1));
    Igray = im2double(rgb2gray(Irgb));

    % --- Igual que en tu código: BW acumulando máscaras por umbral
    BW = zeros(size(Igray));

    for nt = 255:-5:115
        threshold = nt / 255;
        mask = Igray >= threshold;
        mask = bwareaopen(mask, 50);
        BW = BW | mask;

        [BN, LN] = bwboundaries(BW, 'noholes');

        for n = 1:length(BN)
            I4F = (LN == n);

            statsF = regionprops(I4F, 'BoundingBox');
            if ~isempty(statsF)
                rect   = statsF.BoundingBox;   % [x y width height]
                width  = rect(3);
                height = rect(4);
                lado   = max(width, height);   % lado mayor
                if lado > maxSide
                    maxSide = ceil(lado);
                end
            end
        end
    end
end

if maxSide == 0
    warning('No se detectaron regiones. maxSide=0.');
else
    fprintf('Se detectó que el tamaño cuadrado máximo es de %d x %d píxeles.\n', maxSide, maxSide);
end

% ==========================================================
%   PARTE 2: CARACTERISTICAS

% --- Lectura de imágenes
obj = 0;
for img= 1:129
    pathGT = ['C:\Users\lilia\OneDrive\Desktop\PORGRADO\TESIS\BreastCancer\seg_gris\GT\Entrada\', num2str(img) ,'GTM.bmp'];
    pathRGB = ['C:\Users\lilia\OneDrive\Desktop\PORGRADO\TESIS\BreastCancer\seg_gris\GT\Entrada\', num2str(img) ,'rgb_mask.bmp'];

    GT   = imread(pathGT);
    Irgb = imread(pathRGB);

    GT    = logical(GT(:,:,1));
    Igray = im2double(rgb2gray(Irgb));

    % --- Conversiones de color
    Ihsi = rgb2hsi(Irgb);   % <-- definida más abajo
    Ilab = rgb2lab(Irgb);

    % --- Variables base
    BW = zeros(size(Igray));
    AN = [];

    % --- Rango de umbrales
    for nt = 255:-5:115

        threshold = nt / 255;
        mask = Igray >= threshold;
        mask = bwareaopen(mask, 50);
        BW = BW | mask;

        [BN, LN] = bwboundaries(BW, 'noholes');
        C = [];

        for n = 1:length(BN)
            inmg = inmg + 1
            I4F = (LN == n);
                
            

            % stats de la región
            statsF = regionprops(I4F, 'Area', 'Perimeter', 'Eccentricity', 'Centroid', 'BoundingBox');

            obj = obj + 1;
            obj
            % --- Morfología básica
            C(1,n) = statsF.Area;
            C(2,n) = statsF.Perimeter;
            if C(2,n)>0
                C(3,n) = (4*pi*C(1,n))/(C(2,n)^2); % Circularidad
            else
                C(3,n) = 0;
            end
            C(4,n) = statsF.Eccentricity;

            % --- EXTRAER DE TODOS LOS CANALES

            % RGB
            Fr = extract_features(I4F, Irgb(:,:,1));
            Fg = extract_features(I4F, Irgb(:,:,2));
            Fb = extract_features(I4F, Irgb(:,:,3));

            % HSI
            Fh = extract_features(I4F, Ihsi(:,:,1));
            Fs = extract_features(I4F, Ihsi(:,:,2));
            Fi = extract_features(I4F, Ihsi(:,:,3));

            % LAB
            Fl  = extract_features(I4F, Ilab(:,:,1));
            Fa  = extract_features(I4F, Ilab(:,:,2));
            Fb2 = extract_features(I4F, Ilab(:,:,3));

            % --- Valor de la GT
            ISL = regionprops(I4F, GT, 'PixelValues');
            if isempty(ISL) || isempty(ISL(1).PixelValues)
                GTval = 1;  % por seguridad, si no hay píxeles en GT
            else
                GTval = mode(double(ISL(1).PixelValues) + 1); % 1 = no tumor, 2 = tumor
            end

            % --- Concatenar todas las características
            C_total(:,obj) = [C(:,n)', ...
                              Fr(1,:), Fg(1,:), Fb(1,:), ...
                              Fh(1,:), Fs(1,:), Fi(1,:), ...
                              Fl(1,:), Fa(1,:), Fb2(1,:), GTval];
            % AN = [AN; C_total(:,obj)];

            %   RECORTE Y NORMALIZACIÓN
            if maxSide > 0
                rect  = statsF.BoundingBox;      % [x y width height]
                rect  = round(rect);
                patch = imcrop(Igray, rect);     % recorte en gris original

                % --- Redimensionar al tamaño CUADRADO MÁXIMO detectado ---
                patchMax = imresize(patch, [maxSide maxSide]);

                % ----------------- ENTRADA RED 32x32 --------------------
                Incnn = imresize(patchMax, [32 32]);
                x2(:,:,inmg) = Incnn;
                d(1,inmg)    = GTval - 1;

                % ----------------- CLASIFICACIÓN POR CARPETA ------------
                if GTval == 1
                    carpetaClase = '1';   % NO TUMOR
                    contClase1 = contClase1 + 1;
                    idx = contClase1;
                else
                    carpetaClase = '2';   % TUMOR
                    contClase2 = contClase2 + 1;
                    idx = contClase2;
                end

                % --- Guardar recortes tamaño máximo en basePath
                outputFolder = fullfile(basePath, carpetaClase);
                if ~exist(outputFolder, 'dir')
                    mkdir(outputFolder);
                end
                filename = fullfile(outputFolder, sprintf('%d.png', idx));
                imwrite(patchMax, filename);

                % --- (Opcional) Guardar también las 32x32 por clase (CNN)
                outputFolder32 = fullfile(basePath32, carpetaClase);
                if ~exist(outputFolder32, 'dir')
                    mkdir(outputFolder32);
                end
                filename32 = fullfile(outputFolder32, sprintf('%d.png', idx));
                imwrite(Incnn, filename32);

                % ======================================================
                % GUARDAR I4F COMPLETA Y RECORTES DE I4F (32x32)
                % ======================================================

                % --- 1) Guardar la máscara COMPLETA I4F (tamaño original)
                outputFolderI4Ffull = fullfile(basePathI4F_full, carpetaClase);
                if ~exist(outputFolderI4Ffull, 'dir')
                    mkdir(outputFolderI4Ffull);
                end
                filenameI4Ffull = fullfile(outputFolderI4Ffull, sprintf('%d.png', idx));
                imwrite(I4F, filenameI4Ffull);

                % --- 2) Guardar el RECORTE (bounding box) de I4F EN 32x32
                I4F_crop = imcrop(I4F, rect);             % recorte binario
                I4F_crop32 = imresize(I4F_crop, [32 32]); % 32x32

                outputFolderI4Fcrop = fullfile(basePathI4F_crop, carpetaClase);
                if ~exist(outputFolderI4Fcrop, 'dir')
                    mkdir(outputFolderI4Fcrop);
                end
                filenameI4Fcrop = fullfile(outputFolderI4Fcrop, sprintf('%d.png', idx));
                imwrite(I4F_crop32, filenameI4Fcrop);

            end

        end
    end
end

% Guardar dataset para la CNN
save('Imagenes_CNN.mat', 'x2', 'd');

save('caracteristicas',"C_total");
AN = C_total';

% --- Guardar para Weka
arffwrite('Igray_multicanales_varias_imagenes129', AN);

fprintf('\nTodas las imágenes de las carpetas 1 y 2 se guardaron con tamaño %d x %d.\n', maxSide, maxSide);
fprintf('Las imágenes para la CNN se guardaron como 32x32 en Imagenes_CNN.mat y en %s.\n', basePath32);



% ==========================================================
% FUNCIÓN AUXILIAR: extracción de características por canal
function F = extract_features(I4F, channel)
    s = regionprops(I4F, channel, 'PixelValues');
    if isempty(s) || isempty(s(1).PixelValues)
        F = zeros(1,7);
        return
    end
    vals = double(s(1).PixelValues);

    F(1) = mean(vals);
    F(2) = std(vals);
    F(3) = mode(vals);

    % Textura GLCM (nivel de gris)
    vals_norm = uint8(255 * mat2gray(vals));
    G = graycomatrix(vals_norm, 'NumLevels', 256, 'Offset', [-1 0]);
    T = graycoprops(G);
    F(4) = T.Contrast;
    F(5) = T.Correlation;
    F(6) = T.Energy;
    F(7) = T.Homogeneity;
end

% ==========================================================
% FUNCIÓN AUXILIAR: conversión RGB a HSI
function HSI = rgb2hsi(RGB)
    RGB = im2double(RGB);
    R = RGB(:,:,1);
    G = RGB(:,:,2);
    B = RGB(:,:,3);

    num = 0.5 * ((R - G) + (R - B));
    den = sqrt((R - G).^2 + (R - B).*(G - B));
    den(den == 0) = eps; 
    theta = acos(num ./ den);

    H = theta;
    H(B > G) = 2*pi - H(B > G);
    H = H / (2*pi);

    % Saturación
    minRGB = min(min(R,G),B);
    S = 1 - (3 ./ (R + G + B + eps)) .* minRGB;

    % Intensidad
    I = (R + G + B) / 3;

    HSI = cat(3, H, S, I);
end
