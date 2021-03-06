%  SingleStateSearch_Disturbance
%
%  Executes the model with the Disturbance Fault Model as a basis in an
%  explorative manner, attempting to provide a view of the input space
%
%  Author: Alvin Stanescu
%

% add all the paths containing the model and the functions we use
addpath(CT_ModelPath);
addpath(strcat(CT_ScriptsPath, '\ModelExecution'));
addpath(strcat(CT_ScriptsPath, '\ObjectiveFunctions'));
addpath(strcat(CT_ScriptsPath, '\Regression'));
addpath(strcat(CT_ScriptsPath, '\Util'));

% begin logging 
CT_DiaryInit(strcat(CT_UserTempPath,'\ControllerTesterOutput.log'));
try
    % configure the static model configuration parameters and load the
    % model into the system memory
    load_system(CT_ModelFile);
    CT_CheckCorrectOutput(CT_ActualVariableName);
    run(CT_ModelConfigurationFile);
    % double the model simulation time set in the GUI because we need two values for the disturbance fault model
    simulationTime = CT_ModelSimulationTime * 2;
    CT_SetSimulationTime(simulationTime);
    
    % retrieve the model simulation step, as it might have been changed by
    % the configuration script
    CT_ModelTimeStep = CT_GetSimulationTimeStep();
    CT_SimulationSteps=simulationTime/CT_ModelTimeStep;
    
    % compute the region bounds
    RegionXStart = (CT_ModelSimulationTime/CT_Regions) * CT_RegionXIndex;
    RegionXEnd = (CT_ModelSimulationTime/CT_Regions) * (CT_RegionXIndex + 1);

    RegionYStart = CT_DesiredValueRangeStart + ((CT_DesiredValueRangeEnd - CT_DesiredValueRangeStart)/CT_Regions) * CT_RegionYIndex;
    RegionYEnd = CT_DesiredValueRangeStart + ((CT_DesiredValueRangeEnd - CT_DesiredValueRangeStart)/CT_Regions) * (CT_RegionYIndex + 1);
    
    % convert the problem to a minimization problem for use with the
    % (global) optimization toolbox
    hSimulation = @(p)(-1*SimulateModelDisturbance(CT_ModelFile, p(2), CT_DisturbanceAmplitude, CT_DisturbanceSignalType, p(1), CT_DisturbanceDuration, CT_DisturbanceUpTime, CT_ActualValueRangeStart, CT_ActualValueRangeEnd, CT_MaxObjectiveFunctionIndex, CT_SimulationSteps, CT_ModelTimeStep, CT_DesiredVariableName, CT_ActualVariableName, CT_DisturbanceVariableName, CT_TimeStable, CT_TimeStable, CT_SmoothnessStartDifference, CT_ResponsivenessClose, CT_AccelerationDisabled, CT_ModelConfigurationFile));
    lb = [RegionXStart, RegionYStart];
    ub = [RegionXEnd, RegionYEnd];
    
    % build the model if needed
    if (CT_ModelConfigurationFile)
        evalin('base', strcat('run(''',CT_ModelConfigurationFile,''')'));
    end
    assignin('base', CT_DesiredVariableName, CT_GenerateConstantSignal(CT_SimulationSteps, CT_ModelTimeStep, 0));
    assignin('base', CT_DisturbanceVariableName, CT_GenerateConstantSignal(1, CT_SimulationSteps*CT_ModelTimeStep, 0));
    accelbuild(gcs);
    error = false;
    
    switch CT_OptimizationAlgorithm 
        case 'AcceleratedSimulatedAnnealing'
            tic;
            % create a training set and a test set
            [TrainingSet, TestSet, worstObjectiveFunctions] = CT_CreateDataSets(hSimulation, CT_TrainingSetSizeEqualDistance, CT_TrainingSetSizeRandom, CT_ValidationSetSize, RegionXStart, RegionXEnd, RegionYStart, RegionYEnd, CT_RefinedCandidatePoints, CT_RefinementPoints, CT_StartPoint);
                        
            % attempt to find the best regression
            CT_DiaryLog('Finding the best regression.');
            [mdl, error, ChosenRegressionFunction, BestRMSE, BestRegressionFunction, RegressionQualityThreshold] = CT_ChooseBestRegression(TrainingSet, TestSet, CT_ModelQuality, worstObjectiveFunctions(1,1));
            
            if (error == true)
                % if an error is present we report that accelerated
                % simulated annealing cannot be performed
                CT_DiaryLog('Fitting error, severe outliers present in the simulation data. Accelerated Simulated Annealing cannot be performed.');
            else
                CT_DiaryLog('Successful regressed model computation, using model to speed up the simulated annealing.');

                % use the regression to speed up Simulated Annealing
                hRegressionSimulation = @(p)(mdl.Function(mdl.Regression, p));
                fastSaPlot = @(options,optimvalues,flag)(SingleStateSearch_LogIteration(options,optimvalues,flag,100,'SimulatedAnnealingModel'));
                saoptions = saoptimset('AnnealingFcn',@annealingfast,'MaxIter',1000,'OutputFcns',fastSaPlot);
                [p,objectiveFunctionValue,exitFlag,output] = simulannealbnd(hRegressionSimulation, TrainingSet.Input(worstObjectiveFunctions(1,1),:), lb, ub, saoptions);
                % use the worst objective function input point as a starting point in Simulated
                % Annealing upon the real model
                % choice of the SA temperature -> http://www.mathworks.com/help/gads/how-simulated-annealing-works.html
                % if value of (new-old) > 3*rmse, the probability is smaller
                % the probability of acceptance increases the smaller the delta is
                % another motivation for using this temperature, is that
                % the point must be close to the point found by performing SA on the regression
                % @annealingfast (default) � Step length equals the current temperature, and direction is uniformly random.
                realSaPlot = @(options,optimvalues,flag)(SingleStateSearch_LogIteration(options,optimvalues,flag,10,'SimulatedAnnealingAccelerated'));
                saoptions = saoptimset('AnnealingFcn',@annealingfast,'MaxIter',100,'InitialTemperature',mdl.RMSE*3,'OutputFcns',realSaPlot); %@annealingfast, @annealingboltz, HybridFcn - interesting
                [p,objectiveFunctionValue,exitFlag,output] = simulannealbnd(hSimulation, p, lb, ub, saoptions);
                
                % convert the obj. function value back
                objectiveFunctionValue = -1 * objectiveFunctionValue;
            end
            
            toc;
        case 'SimulatedAnnealing'
            tic;
            
            realSaPlot = @(options,optimvalues,flag)(SingleStateSearch_LogIteration(options,optimvalues,flag,10,'SimulatedAnnealing'));
            saoptions = saoptimset('AnnealingFcn',@annealingfast,'MaxIter',1500,'OutputFcns',realSaPlot);
            [p, objectiveFunctionValue, exitFlag, output] = simulannealbnd(hSimulation, CT_StartPoint, lb, ub, saoptions);
            
            % convert the obj. function value back
            objectiveFunctionValue = -1 * objectiveFunctionValue;
            toc;
        case 'PatternSearch'
            tic;
            options = psoptimset('CompletePoll','on','UseParallel',true,'Display','iter');
            [p, objectiveFunctionValue] = patternsearch(hSimulation, CT_StartPoint, [], [], [], [], lb, ub, [], options);
            objectiveFunctionValue = -1 * objectiveFunctionValue;
            toc;
        case 'MultiStart'   
            tic;
            problem = createOptimProblem('fmincon', ...
                'objective', hSimulation, ...
                'x0', CT_StartPoint, ...
                'lb', lb, ...
                'ub', ub, ...
                'options', optimoptions(@fmincon,'Display','off'));
            ms = MultiStart('UseParallel',true,'Display','iter');
            [p, objectiveFunctionValue] = run(ms,problem,20);
            duration = toc;
            display(strcat('runningTime=', num2str(duration)));
            objectiveFunctionValue = -1 * objectiveFunctionValue;
        case 'GlobalSearch'  
            tic;
            problem = createOptimProblem('fmincon', ...
                'objective', hSimulation, ...
                'x0', CT_StartPoint, ...
                'lb', lb, ...
                'ub', ub, ...
                'options', optimoptions(@fmincon,'Display','off'));
            gs = GlobalSearch('Display','iter');
            [p, objectiveFunctionValue] = run(gs,problem);
            objectiveFunctionValue = -1 * objectiveFunctionValue;
            toc;

        case 'GeneticAlgorithm'
            %% run the genetic algorithm to find a point close to the minimum
            tic;
            rng('default') % for reproducibility
            gaoptions = gaoptimset('Generations',10,'UseParallel',true,'TolFun',1/10000, 'PlotFcns',{@gaplotbestf,@gaplotmaxconstr},'Display','iter');
            [p, objectiveFunctionValue] = ga(hSimulation, 2, [], [], [], [], lb, ub, [], gaoptions);
            disp('Genetic algorithm finished');

            %% finish it off with fmincon
            options = optimoptions(@fmincon,'UseParallel',true,'Algorithm','sqp','Display','iter');
            [p, objectiveFunctionValue] = fmincon(hSimulation, p, [], [], [], [], [RegionXStart RegionYStart], [RegionXEnd RegionYEnd], [],options);
            disp('Fmincon finished');
            objectiveFunctionValue = -1 * objectiveFunctionValue;
            toc;

    end
    
    
    if ~error
    	SingleStateSearch_Step_SaveResults(p, objectiveFunctionValue, CT_TempPath);
        display('Successful termination of the random exploration process.');
    end
    diary off;
catch e
    display('Error during random exploration: ');
    display(getReport(e));
    diary off;
end
