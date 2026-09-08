clc; clear; close all;

load('Imagenes_CNN.mat')
% Debe contener:
%   x2 : parches para la CNN
%   d  : etiquetas 0/1 por objeto (N objetos)

%% CREATE A CNN
H = 32;    % height of 2-D input
W = 32;    % width of 2-D input

% Create connection matrices                
%OPCION 2
cm1 = cnn_cm('full', 1, 6);  % input to layer C1
cm2 = cnn_cm('1-to-1', 6);   % C1 to S2
cm3 = [ 1 0 0 0 1 1 1 0 0 1 1 1 1 0 1 1; 
        1 1 0 0 0 1 1 1 0 0 1 1 1 1 0 1;
        1 1 1 0 0 0 1 1 1 0 0 1 0 1 1 1;
        0 1 1 1 0 0 1 1 1 1 0 0 1 0 1 1;
        0 0 1 1 1 0 0 1 1 1 1 0 1 1 0 1;
        0 0 0 1 1 1 0 0 1 1 1 1 0 1 1 1]; % S2 to layer C3
cm4 = cnn_cm('1-to-1', 16);   % C3 to S4
cm5 = cnn_cm('1-to-1', 16);   % S4 to C5
cm6 = cnn_cm('full',16,1);    % C5 to F6
c = {
    cm1, cm2, cm3, cm4, cm5, cm6
    };

% Receptive sizes for each layer
rec_size = [5 5;   % C1
            2 2;   % S2
            3 3;   % C3
            2 2;   % S4
            0 0;   % C5 auto calculated
            0 0];  % F6 auto calculated

% Transfer function
tf_fcn = {
    'tansig',...   % layer C1
    'purelin',...  % layer S2
    'tansig',...   % layer C3
    'purelin',...  % layer S4
    'tansig',...   % layer C5
    'tansig'};     % layer F6 output

% Training method
train_method = 'rprop';        % 'gd'

% Create CNN
net = cnn_new([H W], c, rec_size, tf_fcn, train_method);

%% Network training CELL CLASSIFICATION
d3 = d;                         % etiquetas 0/1 para la CNN

x3 = double(x2(:,:,:,1));       % canal L, tal como lo tenías
net.train.epochs = 100;         % o 1 si solo quieres probar
[new_net, tr] = cnn_train(net, x3, d3);
save('trained_netCNN_L.mat', 'new_net');

%% training performance     

d3 = d;                         % mismas etiquetas

x3 = double(x2(:,:,:,1));       % de nuevo canal L
load('trained_netCNN_L.mat')        
y_test = cnn_sim(new_net, x3);  % network output

cr_test = sum((y_test{end} > 0) == (d3 >= 0)) / length(d3) * 100;
fprintf('Classification rate (test): cr = %2.2f%%\n', cr_test);

% Características de la capa C5
featuresTest = y_test{5};       % típicamente: [hC5 x wC5 x N x Fmaps]

%% === EXTRACCIÓN DE FEATURES CNN (C5) ===

[hC5, wC5, N, Fmaps] = size(featuresTest);      % N = #objetos

% Reordenar a [N x (Fmaps*hC5*wC5)]
featuresTestL = reshape( permute(featuresTest, [3 4 1 2]), ...
                         [N, Fmaps*hC5*wC5] );
% Si C5 es 1x1, queda [N x 16]

% Asegurar que d sea columna
if isrow(d)
    d = d';
end

% Para WEKA la clase será 1 y 2 (0->1, 1->2)
d_clase = d + 1;                % N x 1

%% === 1) ARFF SOLO CON CNN (SIEMPRE SE GENERA) ===

% Matriz [features CNN | clase]
Features_cnn_only = [featuresTestL, d_clase];

arffwrite('CNN_only', Features_cnn_only);
disp('Archivo CNN_only.arff generado (solo características CNN + clase 1/2).');

%% === 2) FUSIÓN CON CARACTERÍSTICAS CLÁSICAS (C_total) ===

load('caracteristicas.mat');    % aquí está C_total (68 x N_objetos)

if exist('C_total','var')
    % C_total: 68 x Nobjetos  --> transponemos:
    %   filas = objetos, columnas = características
    Features = C_total';        % [N_objetos x 68]

    [N_feat, M_feat] = size(Features);

    if N_feat ~= N
        error('No coincide el número de objetos: C_total (transpuesto) = %d, CNN = %d', ...
              N_feat, N);
    end

    % Suponemos que la ÚLTIMA columna de Features es la clase GTval (1/2)
    Features_sinClase = Features(:,1:end-1);
    clase_GT = Features(:,end);          % debería coincidir con d_clase

    % (Opcional) podrías usar clase_GT en lugar de d_clase:
    % Features_final = [Features_sinClase, featuresTestL, clase_GT];

    % Yo dejo d_clase para que vaya amarrado exactamente a la salida usada en la CNN:
    Features_final = [Features_sinClase, featuresTestL, d_clase];

    arffwrite('CNNdriven', Features_final);
    disp('Archivo CNNdriven.arff generado (clásicas + CNN + clase 1/2).');
else
    warning('En caracteristicas.mat no existe C_total. Solo se generó CNN_only.arff.');
end