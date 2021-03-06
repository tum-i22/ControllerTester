﻿using FM4CC.ExecutionEngine;
using FM4CC.FaultModels.Disturbance.Parsers;
using FM4CC.TestCase;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Timers;

namespace FM4CC.FaultModels.Disturbance
{
    internal class WorstCaseScenarioWorker : BackgroundWorker
    {
        internal FM4CCException Exception { get; set; }
        internal IList<DataGridHeatPoint> SelectedRegions { get; set; }
        internal IList<TestCase.FaultModelTesterTestCase> TestCases { get; set; }
        internal Action<string> Logger { get; set; }

        private static System.Timers.Timer aTimer;
        private DisturbanceFaultModel fm;
        private bool isRunning;

        internal WorstCaseScenarioWorker()
        {
            this.Exception = null;
            this.WorkerReportsProgress = true;
            this.WorkerSupportsCancellation = true;
            this.DoWork += singleStateWorker_DoWork;
        }

        private void singleStateWorker_DoWork(object sender, DoWorkEventArgs e)
        {
            try
            {
                this.Exception = null;
                isRunning = false;
                if (SelectedRegions == null) throw new FM4CCException("Search regions not set");

                aTimer = new System.Timers.Timer(100);
                aTimer.Elapsed += new ElapsedEventHandler(OnTimedEvent);
                aTimer.Enabled = true;
                aTimer.AutoReset = true;

                fm = e.Argument as DisturbanceFaultModel;
                ExecutionInstance currentTestProject = fm.ExecutionInstance;

                string message = null;
                fm.ExecutionEngine.AcquireProcess();

                // Sets up the environment of the execution engine
                fm.ExecutionInstance = currentTestProject;
                fm.SetUpEnvironment();

                e.Result = true;

                int i = 0;
                foreach (DataGridHeatPoint region in SelectedRegions)
                {
                    int requirementIndex = 1;

                    switch (region.Requirement)
                    {
                        case "Stability":
                            requirementIndex = 1;
                            break;
                        case "Precision":
                            requirementIndex = 2;
                            break;
                        case "Smoothness":
                            requirementIndex = 3;
                            break;
                        case "Responsiveness":
                            requirementIndex = 4;
                            break;
                        case "Steadiness":
                            requirementIndex = 5;
                            break;
                        case "Smoothness Pre-Disturbance":
                            requirementIndex = 6;
                            break;
                        case "Responsiveness Pre-Disturbance":
                            requirementIndex = 7;
                            break;
                        case "Smoothness Post-Disturbance":
                            requirementIndex = 8;
                            break;
                        case "Responsiveness Post-Disturbance":
                            requirementIndex = 9;
                            break;
                    }

                    fm.SetSearchParameters(requirementIndex, region.TimeRegion, region.DesiredRegion, region.ContainedHeatPoint, (string)fm.FaultModelConfiguration.GetValue("OptimizationAlgorithm"));

                    isRunning = true;

                    if (Double.IsInfinity(region.ContainedHeatPoint.Intensity))
                    {
                        i++;
                        this.ReportProgress((int)((double)i / SelectedRegions.Count * 100.0));
                        continue;
                    }
                    message = (string)fm.Run("WorstCaseSearch");

                    if (!message.ToLower().Contains("success"))
                    {
                        if (!message.ToLower().Contains("fitting error"))
                        {
                            e.Result = false;
                            this.Exception = new FM4CCException(message);
                            break;
                        }
                        else
                        {
                            string chosenRegressionFunction = fm.ExecutionEngine.GetVariable("ChosenRegressionFunction");
                            double rmse = fm.ExecutionEngine.GetVariable("BestRMSE");
                            double qualityThreshold = fm.ExecutionEngine.GetVariable("RegressionQualityThreshold");
                            string bestRegressionFunction = fm.ExecutionEngine.GetVariable("BestRegressionFunction");
                            // use the worst point found while computing the training set
                            fm.ExecutionEngine.ExecuteCommand("tmpVar = TrainingSet.Input(worstObjectiveFunctions(1,1),:)");
                            double[,] bestPoint = fm.ExecutionEngine.GetVariable("tmpVar");

                            Logger("Disturbance Fault Model - Accelerated worst case computation for " + region.Requirement + " failed. Unable to fit data to regressed model, falling back to doing simple Simulated Annealing. Best regression function was " + bestRegressionFunction + " (RMSE: " + rmse.ToString() + ", Threshold: " + qualityThreshold.ToString() + ").");
                            fm.SetSearchParameters(requirementIndex, region.TimeRegion, region.DesiredRegion, new DisturbanceHeatPoint(bestPoint[0, 0], bestPoint[0, 1], 0.0, 0.0, false), "SimulatedAnnealing");
                            message = (string)fm.Run("WorstCaseSearch");
                        }
                    }
                    else
                    {
                        string chosenRegressionFunction = fm.ExecutionEngine.GetVariable("ChosenRegressionFunction");
                        double rmse = fm.ExecutionEngine.GetVariable("BestRMSE");
                        double qualityThreshold = fm.ExecutionEngine.GetVariable("RegressionQualityThreshold");

                        Logger("Disturbance Fault Model - Accelerated worst case computation successful for " + region.Requirement + ". Regression function " + chosenRegressionFunction + " selected (RMSE: " + rmse.ToString() + ", Threshold: " + qualityThreshold.ToString() + ").");
                    }
                    i++;
                    this.ReportProgress((int)((double)i / SelectedRegions.Count * 100.0));

                    string worstPointFile = Path.GetDirectoryName(this.fm.ExecutionInstance.GetValue("SUTPath")) + "\\ControllerTesterResults\\SingleStateSearch\\SingleStateSearch_WorstCase.csv";
                    ProcessWorstCaseResults(region, worstPointFile, fm.ToString());
                }

                aTimer.Enabled = false;

                // Tears down the environment
                fm.TearDownEnvironment(false);

                // Relinquishes control of the execution engine
                fm.ExecutionEngine.RelinquishProcess();
            }
            catch (TargetInvocationException)
            {
                e.Result = false;
            }

        }

        private void ProcessWorstCaseResults(DataGridHeatPoint region, string worstPointFile, string faultModelName)
        {
            FaultModelTesterTestCase testCase = new DisturbanceFaultModelTestCase();
            testCase.FaultModel = faultModelName;
            testCase.Name = "Worst " + region.Requirement + " (disturbance) in region (" +
                String.Format("{0:0.##}", region.TimeRegion * region.BaseUnitTime) + " to " +
                String.Format("{0:0.##}", (region.TimeRegion + 1) * region.BaseUnitTime) + ")x(" +
                String.Format("{0:0.##}", region.DesiredRegion * region.BaseUnit) + " to " +
                String.Format("{0:0.##}", (region.DesiredRegion + 1) * region.BaseUnit) + ")";
            testCase.Input = SingleStateSearchParser.Parse(worstPointFile);
            TestCases.Add(testCase);
        }

        private void OnTimedEvent(object sender, ElapsedEventArgs e)
        {
            if (this.CancellationPending)
            {
                if (isRunning)
                {
                    // kill the execution engine and relinquish control
                    aTimer.Enabled = false;
                    fm.ExecutionEngine.Kill();
                    fm.TearDownEnvironment(false);
                    fm.ExecutionEngine.RelinquishProcess();
                }
            }
        }
    }
}
