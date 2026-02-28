classdef SpectralCalibrationConfigurable < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                    matlab.ui.Figure
        GridLayout                  matlab.ui.container.GridLayout
        
        InputBrowseButton           matlab.ui.control.Button
        ConfigurationDropdown       matlab.ui.control.DropDown
        ConfigurationLabel          matlab.ui.control.Label

        UITable                     matlab.ui.control.Table
        SaveCalibrationFileButton   matlab.ui.control.Button
        VisualizePointsButton       matlab.ui.control.Button

        UIAxesXShifts               matlab.ui.control.UIAxes
        UIAxesYShifts               matlab.ui.control.UIAxes
    end

    properties (Access = private)
        % Properties that correspond to app components
        dir_inputpath % path to the input directory
        dir_outputpath % path to the output directory
        wavelengths = [532, 580, 633, 680, 750] % wavelengths to be calibrated
        speccali_struct % spectral calibration structure initialization
        files % list of csv files in the input directory

        data

        % Configuration options
        % Coordinate system: x-axis (left=small, right=large), y-axis (top=small, bottom=large)
        % 'vertical' = split on x-coordinate (for left/right configurations)
        % 'horizontal' = split on y-coordinate (for up/down configurations)
        split_axis = 'vertical';  % 'vertical' or 'horizontal'
        order0_first = true;      % true = 0th order is smaller values (left/up), false = larger values (right/down)

        % other internal properties
        fx
        fy
        locs0
        locs1
        xscale
        yscale
        xshift
        yshift
        x0centroid
        y0centroid
        wls
    end

    % Callbacks that handle component events
    methods (Access = private)

        % Configuration dropdown changed
        function ConfigurationDropdownChanged(app, ~)
            config_value = app.ConfigurationDropdown.Value;
            
            switch config_value
                case '0th left, 1st right'  % Split on X values (left=small x, right=large x)
                    app.split_axis = 'vertical';
                    app.order0_first = true;
                case '0th right, 1st left'  % Split on X values (reversed)
                    app.split_axis = 'vertical';
                    app.order0_first = false;
                case '0th up, 1st down'     % Split on Y values (up=small y, down=large y)
                    app.split_axis = 'horizontal';
                    app.order0_first = true;
                case '0th down, 1st up'     % Split on Y values (reversed)
                    app.split_axis = 'horizontal';
                    app.order0_first = false;
            end
            
            % Re-run calibration with new settings
            if ~isempty(app.data) && any(~cellfun(@isempty, app.data))
                RunCalibration(app);
            end
        end

        % Button pushed function: VisualizePointsButton
        function VisualizePointsButtonPushed(app, ~)
            % Create a new figure window to visualize the 0th and 1st order points
            fig = figure('Name', 'Localization Visualization', 'NumberTitle', 'off', 'Position', [200 200 900 700]);
            
            % Get the selected wavelength (first file in the table)
            if isempty(app.UITable.Data) || height(app.UITable.Data) == 0
                msgbox('No data to visualize. Please load CSV files first.', 'Info');
                return
            end
            
            ifile = 1;  % visualize the first file
            
            % Extract localizations for this file
            locs0_current = squeeze(app.locs0(ifile, :, :));
            locs1_current = squeeze(app.locs1(ifile, :, :));
            
            % Create the plot
            ax = axes(fig);
            hold(ax, 'on');
            
            % Plot 0th order points in red
            scatter(ax, locs0_current(:, 1), locs0_current(:, 2), 50, 'r', 'filled', 'DisplayName', '0th Order');
            
            % Plot 1st order points in blue
            scatter(ax, locs1_current(:, 1), locs1_current(:, 2), 50, 'b', 'filled', 'DisplayName', '1st Order');
            
            hold(ax, 'off');
            
            % Flip y-axis (larger y-values at the top in image coordinates)
            set(ax, 'YDir', 'reverse');
            
            % Add labels and formatting
            xlabel(ax, 'X [nm]', 'FontSize', 12);
            ylabel(ax, 'Y [nm]', 'FontSize', 12);
            wavelength = app.UITable.Data{ifile, 2};
            title(ax, sprintf('Localization Points at %.0f nm', wavelength), 'FontSize', 14);
            grid(ax, 'on');
            legend(ax, 'FontSize', 11, 'Location', 'best');
            axis(ax, 'equal');
            
            % Set plot properties
            set(ax, 'FontSize', 11);
        end

        % When the wavelength in the UITable is edited
        function UITableCellEdit(app, event)
            % get the row and column of the edited cell
            row = event.Indices(1);
            col = event.Indices(2);

            % get the selected wavelengths
            selected_wavelengths = app.UITable.Data{:, 2};
            % error handling for no wavelengths selected
            if sum(selected_wavelengths > 0) < 2
                errordlg('Insufficient wavelengths selected. Please input at least two wavelengths.', 'Error');
                return
            end

            if col == 1
                if isempty(app.UITable.Data{row, 1})
                    app.UITable.Data(row, :) = [];
                else
                    % check if the file exists
                    if ~isfile(fullfile(app.dir_inputpath, app.UITable.Data{row, 1}))
                        errordlg('The file does not exist. Please select a valid file.', 'Error');
                        return
                    end

                    % update the filename in the table
                    app.files{row, 'name'} = app.UITable.Data{row, 1};

                    % load the data from the file
                    LoadData(app, row);
                end
            elseif col == 2
                if (app.UITable.Data{row, 2} == 0) || isnan(app.UITable.Data{row, 2})
                    app.UITable.Data(row, :) = [];
                end
            end

            RunCalibration(app);
        end

        % Button pushed function: InputBrowseButton
        function InputBrowseButtonPushed(app, ~)
            input_dir = uigetdirfile;
            % error handling for cancel button
            if isempty(input_dir)
                return
            end

            if length(input_dir) == 1
                % check if this is a directory
                if isfolder(input_dir)
                    app.dir_inputpath = input_dir;
                else
                    errordlg('Please select a valid input directory.', 'Error');
                    return
                end
                
                csv_files = dir(fullfile(app.dir_inputpath, '*.csv'));

                if isempty(csv_files)
                    errordlg('No CSV files found in the input directory.', 'Error');
                    return
                end

                app.files = struct2table(csv_files, 'AsArray', true);
                
            else % if this is a list of files
                [app.dir_inputpath, ~, ref_ext] = fileparts(input_dir{1});
                if ~strcmpi(ref_ext, '.csv')
                    errordlg('Please select CSV files.', 'Error');
                    return
                end

                input_filenames = cell(length(input_dir), 1);
                input_isdir = cellfun(@isfolder, input_dir);
                for ii = 1:length(input_dir)
                    [~, name, ext] = fileparts(input_dir{ii});
                    assert(strcmp(ext, '.csv'), 'All files must be CSV format.');
                    input_filenames{ii} = strcat(name, ext);
                end
                app.files = table(input_filenames, input_isdir, ...
                    'VariableNames', {'name', 'isdir'});
            end
            
            app.dir_outputpath = fullfile(app.dir_inputpath, 'speccali.mat');
            figure(app.UIFigure); % bring the app to the front
            app.UITable.Enable = 'on';
            LoadTable(app);
            app.data = cell(height(app.files), 1);
            LoadData(app);
            RunCalibration(app);
        end

        function LoadTable(app, ~)
            % try to match the files to a wavelength each
            app.files{:, 'wavelength'} = zeros(height(app.files), 1);
            
            % if there are fewer files than wavelengths, we trim the wavelength array
            if height(app.files) < length(app.wavelengths)
                app.wavelengths = app.wavelengths(1:height(app.files));
            end

            app.files{1:length(app.wavelengths), 'wavelength'} = app.wavelengths(:);

            % update the UITable with the filenames and wavelengths
            app.UITable.Data = app.files(:, {'name', 'wavelength'});

            % check if we have any empty cells in the table
            if any((app.UITable.Data{:, 2}) == 0)
                % Some wavelengths could not be matched to the csv files.
                return
            end
        end

        function LoadData(app, idx)
            if nargin > 1
                load_data(app, idx);
            else
                % load all the data
                for idx = 1:height(app.files)
                    load_data(app, idx);
                end
            end
        end

        function RunCalibration(app, ~)
            % calculate the spectral calibration
            speccali_localizations(app);
            updatePlots(app);
            
            app.SaveCalibrationFileButton.Enable = 'on';
            app.VisualizePointsButton.Enable = 'on';
        end

        % Update both X and Y shift plots
        function updatePlots(app, ~)
            updateUIAxesXShifts(app);
            updateUIAxesYShifts(app);
        end

        % update UIAxesXShifts with the x-shift vs wavelength
        function updateUIAxesXShifts(app, ~)
            if ~isstruct(app.speccali_struct)
                return
            end
            cla(app.UIAxesXShifts);
            plot(app.UIAxesXShifts, app.speccali_struct.wavelengths, app.speccali_struct.xshift, 'ko');
            hold(app.UIAxesXShifts, 'on');
            wavelength_fine = linspace(min(app.speccali_struct.wavelengths), max(app.speccali_struct.wavelengths), 101);
            plot(app.UIAxesXShifts, wavelength_fine, dwp_wl2px(wavelength_fine, app.speccali_struct.fx), 'k-')
            hold(app.UIAxesXShifts, 'off');
            xlabel(app.UIAxesXShifts, 'Wavelength (nm)');
            ylabel(app.UIAxesXShifts, 'X Shift (nm)');
            title(app.UIAxesXShifts, 'X Shift vs Wavelength');
        end

        % update UIAxesYShifts with the y-shift vs wavelength
        function updateUIAxesYShifts(app, ~)
            if ~isstruct(app.speccali_struct)
                return
            end
            cla(app.UIAxesYShifts);
            plot(app.UIAxesYShifts, app.speccali_struct.wavelengths, app.speccali_struct.yshift, 'bo');
            hold(app.UIAxesYShifts, 'on');
            wavelength_fine = linspace(min(app.speccali_struct.wavelengths), max(app.speccali_struct.wavelengths), 101);
            plot(app.UIAxesYShifts, wavelength_fine, dwp_wl2px(wavelength_fine, app.speccali_struct.fy), 'b-')
            hold(app.UIAxesYShifts, 'off');
            xlabel(app.UIAxesYShifts, 'Wavelength (nm)');
            ylabel(app.UIAxesYShifts, 'Y Shift (nm)');
            title(app.UIAxesYShifts, 'Y Shift vs Wavelength');
        end

        % Button pushed function: SaveCalibrationFileButton
        function SaveCalibrationFileButtonPushed(app, ~)
            % get the output file path from the user
            [file, output_path] = uiputfile({'*.mat', 'MAT-files (*.mat)'}, 'Save Calibration File', app.dir_outputpath);

            % error handling for cancel button
            if ~output_path
                return
            end

            app.dir_outputpath = fullfile(output_path, file);

            % save the calibration file
            speccali = app.speccali_struct;
            save(app.dir_outputpath, 'speccali');
            
            msgbox(sprintf('Calibration file saved to:\n%s', app.dir_outputpath), 'Success');
        end

        function load_data(app, ifile)
            app.InputBrowseButton.Enable = 'off';
            app.InputBrowseButton.Text = 'Loading...';
            drawnow;

            % get the filename
            filename = app.files{ifile, 'name'}{:};

            % load the data from the csv file
            csvdata = readtable(fullfile(app.dir_inputpath, filename), 'preservevariablenames', true);
            app.data{ifile} = csvdata;

            app.InputBrowseButton.Enable = 'on';
            app.InputBrowseButton.Text = 'Browse';
        end

        % Core app for spectral calibration with configurable order/orientation
        function speccali_localizations(app, ~)
            file_table = app.UITable.Data;

            nfiles = height(file_table);
            
            % get a reference file for the number of localizations
            csvdata = app.data{1};
            nlocs = height(csvdata);
            app.xshift = zeros(nfiles, 1);
            app.yshift = zeros(nfiles, 1);
            wls_temp = file_table{:, 'wavelength'};
            app.wls = wls_temp(:)';
            
            assert(mod(nlocs, 2) == 0, 'The number of localizations in the csv files must be even.');
            app.locs0 = zeros(nfiles, floor(nlocs/2), 2);
            app.locs1 = zeros(nfiles, floor(nlocs/2), 2);

            x0centroids = zeros(nfiles, 1);
            y0centroids = zeros(nfiles, 1);

            for ifile = 1:nfiles
                csvdata = app.data{ifile};
                % check that the number of localization is the same as the reference file
                assert(height(csvdata) == nlocs, 'The number of localizations in file %d is not consistent.', ifile);
            
                % split the localizations based on the configured axis
                [order0, order1] = split_localizations_by_axis(app, csvdata);
            
                % get the number of localizations
                n0 = height(order0);
                n1 = height(order1);
            
                assert(n0 == n1, 'The number of localizations in the two orders are not equal.');
            
                % get the mean values of the localizations
                x0 = mean(order0{:, 'x [nm]'});
                y0 = mean(order0{:, 'y [nm]'});
                x1 = mean(order1{:, 'x [nm]'});
                y1 = mean(order1{:, 'y [nm]'});

                x0centroids(ifile) = x0;
                y0centroids(ifile) = y0;
            
                % calculate the shift between orders
                app.xshift(ifile) = x1 - x0;
                app.yshift(ifile) = y1 - y0;
                
                app.locs0(ifile, :, :) = order0{:, {'x [nm]', 'y [nm]'}};
                app.locs1(ifile, :, :) = order1{:, {'x [nm]', 'y [nm]'}};
            end

            app.x0centroid = mean(x0centroids);
            app.y0centroid = mean(y0centroids);

            compute_calibration_curve(app);
            compute_scaling(app);
            prepare_output(app);
        end

        function [order0, order1] = split_localizations_by_axis(app, csvdata)
            % Split localizations based on configured axis and order
            x_vals = csvdata{:, 'x [nm]'};
            y_vals = csvdata{:, 'y [nm]'};
            
            if strcmp(app.split_axis, 'vertical')
                % Split on x-coordinate (vertical dispersion)
                split_val = mean(x_vals);
                if app.order0_first
                    order0 = csvdata(x_vals < split_val, :);
                    order1 = csvdata(x_vals >= split_val, :);
                else
                    order0 = csvdata(x_vals >= split_val, :);
                    order1 = csvdata(x_vals < split_val, :);
                end
            else  % 'horizontal'
                % Split on y-coordinate (horizontal dispersion)
                split_val = mean(y_vals);
                if app.order0_first
                    order0 = csvdata(y_vals < split_val, :);
                    order1 = csvdata(y_vals >= split_val, :);
                else
                    order0 = csvdata(y_vals >= split_val, :);
                    order1 = csvdata(y_vals < split_val, :);
                end
            end
        end

        function compute_calibration_curve(app, ~)
            app.fx = dwp_fit(app.wls, app.xshift);
            app.fy = dwp_fit(app.wls, app.yshift);
        end

        function prepare_output(app, ~)
            % prepare the output structure
            speccali.xscale = app.xscale;
            speccali.yscale = app.yscale;
            speccali.xshift = app.xshift;
            speccali.yshift = app.yshift;
            speccali.xshift_mean = mean(app.xshift);
            speccali.yshift_mean = mean(app.yshift);
            speccali.x0centroid = app.x0centroid;
            speccali.y0centroid = app.y0centroid;
            speccali.fx = app.fx;
            speccali.fy = app.fy;
            speccali.wavelengths = app.wls;
            speccali.split_axis = app.split_axis;
            speccali.order0_first = app.order0_first;

            app.speccali_struct = speccali;
        end

        function compute_scaling(app, ~)
            file_table = app.UITable.Data;
            nfiles = height(file_table);
            
            for ifile = 1:nfiles
                % here we want to calculate the magnification factors in the x and y directions
                % we first match the localizations of the zeroth and first order
                % then we calculate the magnification factors

                % subtract the (expected) shift from the x and y values
                expected_xshift = dwp_wl2px(app.wls(ifile), app.fx);
                expected_yshift = dwp_wl2px(app.wls(ifile), app.fy);

                app.locs1(ifile, :, 1) = app.locs1(ifile, :, 1) - expected_xshift;
                app.locs1(ifile, :, 2) = app.locs1(ifile, :, 2) - expected_yshift;

                [matched_locs0, matched_locs1] = match_localizations(app, ifile);

                % get the linear fit
                px = polyfit(matched_locs0(:, 1), matched_locs1(:, 1), 1);
                py = polyfit(matched_locs0(:, 2), matched_locs1(:, 2), 1);

                app.xscale(ifile) = px(1);
                app.yscale(ifile) = py(1);
            end
        end

        function [matched_locs0, matched_locs1] = match_localizations(app, ifile)
            % intialize the variables to store pairs of closest localizations
            matched_idx0 = nan(min([size(app.locs0,2), size(app.locs1,2)]), 1);
            matched_idx1 = matched_idx0;
            
            % get the x and y coordinates of the current frame
            tmp_x0 = app.locs0(ifile, :, 1);
            tmp_y0 = app.locs0(ifile, :, 2);
            tmp_x1 = app.locs1(ifile, :, 1);
            tmp_y1 = app.locs1(ifile, :, 2);
            
            % get a temporary index
            tmp_idx0 = 1:size(app.locs0, 2);
            tmp_idx1 = 1:size(app.locs1, 2);
            
            % perform knnsearch to find the closest localizations
            knn_idx1 = knnsearch([tmp_x0(:), tmp_y0(:)], [tmp_x1(:), tmp_y1(:)], 'k', 1);
            knn_idx0 = knnsearch([tmp_x1(:), tmp_y1(:)], [tmp_x0(:), tmp_y0(:)], 'k', 1);
            
            % find the mutual closest localizations
            if ~isempty(knn_idx0)
                mutual_idx0 = find(knn_idx1(knn_idx0) == (1:length(knn_idx0))');
            else
                mutual_idx0 = [];
            end
            
            if ~isempty(knn_idx1)
                mutual_idx1 = find(knn_idx0(knn_idx1) == (1:length(knn_idx1))');
            else 
                mutual_idx1 = [];
            end
            
            if ~isempty(mutual_idx0) && ~isempty(mutual_idx1)
                % assert that the mutual indices have the same length
                assert(length(mutual_idx0) == length(mutual_idx1));
                matched_idx0 = tmp_idx0(mutual_idx0);
                matched_idx1 = tmp_idx1(mutual_idx1);
            end
            
            % remove the nan values
            matched_idx0 = matched_idx0(~isnan(matched_idx0));
            matched_idx1 = matched_idx1(~isnan(matched_idx1));
                
            matched_locs0 = squeeze(app.locs0(ifile, matched_idx0, :));
            matched_locs1 = squeeze(app.locs1(ifile, matched_idx1, :));
        end
    end

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Create UIFigure and hide until all components are created
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 1200 600];
            app.UIFigure.Name = 'Spectral Calibration (Configurable)';

            % Create GridLayout with 3 columns for table + 2 plot axes
            app.GridLayout = uigridlayout(app.UIFigure);
            app.GridLayout.ColumnWidth = {'2x', '3x', '3x'};
            app.GridLayout.RowHeight = {35, 35, '1x', 35};
            app.GridLayout.RowSpacing = 5;
            app.GridLayout.ColumnSpacing = 5;

            % Create InputBrowseButton
            app.InputBrowseButton = uibutton(app.GridLayout, 'push');
            app.InputBrowseButton.Layout.Row = 1;
            app.InputBrowseButton.Layout.Column = 1;
            app.InputBrowseButton.Text = 'Browse';
            app.InputBrowseButton.ButtonPushedFcn = createCallbackFcn(app, @InputBrowseButtonPushed, true);

            % Create SaveCalibrationFileButton
            app.SaveCalibrationFileButton = uibutton(app.GridLayout, 'push');
            app.SaveCalibrationFileButton.Layout.Row = 1;
            app.SaveCalibrationFileButton.Layout.Column = 2;
            app.SaveCalibrationFileButton.Text = 'Save Calibration File';
            app.SaveCalibrationFileButton.ButtonPushedFcn = createCallbackFcn(app, @SaveCalibrationFileButtonPushed, true);
            app.SaveCalibrationFileButton.Enable = 'off';
            
            % Create VisualizePointsButton
            app.VisualizePointsButton = uibutton(app.GridLayout, 'push');
            app.VisualizePointsButton.Layout.Row = 1;
            app.VisualizePointsButton.Layout.Column = 3;
            app.VisualizePointsButton.Text = 'Visualize Points';
            app.VisualizePointsButton.ButtonPushedFcn = createCallbackFcn(app, @VisualizePointsButtonPushed, true);
            app.VisualizePointsButton.Enable = 'off';

            % Create ConfigurationLabel
            app.ConfigurationLabel = uilabel(app.GridLayout);
            app.ConfigurationLabel.Text = 'Configuration:';
            app.ConfigurationLabel.Layout.Row = 2;
            app.ConfigurationLabel.Layout.Column = 1;
            app.ConfigurationLabel.HorizontalAlignment = 'left';
            
            % Create ConfigurationDropdown (spanning columns 2-3)
            app.ConfigurationDropdown = uidropdown(app.GridLayout);
            app.ConfigurationDropdown.Items = {'0th left, 1st right', '0th right, 1st left', '0th up, 1st down', '0th down, 1st up'};
            app.ConfigurationDropdown.Value = '0th up, 1st down';
            app.ConfigurationDropdown.Layout.Row = 2;
            app.ConfigurationDropdown.Layout.Column = [2 3];
            app.ConfigurationDropdown.ValueChangedFcn = createCallbackFcn(app, @ConfigurationDropdownChanged, true);

            % Create UITable (left column, row 3)
            app.UITable = uitable(app.GridLayout);
            app.UITable.ColumnName = {'Filename'; 'Wavelength (nm)'};
            app.UITable.ColumnWidth = {'1x', '1x'};
            app.UITable.RowName = {};
            app.UITable.Layout.Row = 3;
            app.UITable.Layout.Column = 1;
            app.UITable.ColumnEditable = [true, true];
            app.UITable.CellEditCallback = createCallbackFcn(app, @UITableCellEdit, true);
            app.UITable.Enable = 'off';

            % Create UIAxesXShifts (middle column, row 3)
            app.UIAxesXShifts = uiaxes(app.GridLayout);
            app.UIAxesXShifts.Layout.Row = 3;
            app.UIAxesXShifts.Layout.Column = 2;
            app.UIAxesXShifts.Box = 'on';
            app.UIAxesXShifts.XGrid = 'on';
            app.UIAxesXShifts.YGrid = 'on';
            xlabel(app.UIAxesXShifts, 'Wavelength (nm)')
            ylabel(app.UIAxesXShifts, 'X Shift (nm)')
            title(app.UIAxesXShifts, 'X-Shift Calibration')

            % Create UIAxesYShifts (right column, row 3)
            app.UIAxesYShifts = uiaxes(app.GridLayout);
            app.UIAxesYShifts.Layout.Row = 3;
            app.UIAxesYShifts.Layout.Column = 3;
            app.UIAxesYShifts.Box = 'on';
            app.UIAxesYShifts.XGrid = 'on';
            app.UIAxesYShifts.YGrid = 'on';
            xlabel(app.UIAxesYShifts, 'Wavelength (nm)')
            ylabel(app.UIAxesYShifts, 'Y Shift (nm)')
            title(app.UIAxesYShifts, 'Y-Shift Calibration')

            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)
        % Construct app
        function app = SpectralCalibrationConfigurable

            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
            registerApp(app, app.UIFigure)
            
            addpath(fullfile(pwd,'lib'));
            addpath(fullfile(pwd,'lib/dwp_scripts'));
            addpath(fullfile(pwd,'lib/bioformats_tools'));

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.UIFigure)
        end
    end

    % Event handling
    events
        CalibrationFileSaved  % Event sent when the calibration file is saved
    end
end
