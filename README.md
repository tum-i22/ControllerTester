# Controller Tester
*Copyright 2014 Alvin Stanescu, [Software Engineering Chair I22, Technische Universität München](https://www22.in.tum.de/en/home/)*

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

This software is provided with no liability whatsoever and is an Alpha version, therefore **use AT YOUR OWN RISK!**

This software is based on the work *"Automated Model-in-the-Loop Testing of Continuous Controllers Using Search"*
by *Reza Matinnejad, Shiva Nejati, Lionel C. Briand, Thomas Bruckmann and Claude Poull.*, published in *Search Based Software Engineering Lecture Notes in Computer Science Volume 8084, 2013, pp 141-157*.
A digital copy is available from http://dx.doi.org/10.1007/978-3-642-39742-4_12.

## Installer

An installer is available at https://sourceforge.net/projects/controllertester/.

## Requirements
To be able to compile the Controller Tester, the following software is needed:
* **Visual Studio 2013** or newer, with .NET Framework 4.5.1 (however, Visual Studio 2012 with .NET Framework 4.5 should also work if the target framework of the solution is changed)
* The MahApps.Metro UI Framework (NuGet, downloads automatically)
* log4net (NuGet, downloads automatically)
  
To be able to run the Controller Tester, the following software is required:
* a PC with Windows Vista SP2, Windows 7 SP1, Windows 8 or Windows 8.1 with the *.NET Framework 4.5.1* installed
* **MATLAB 2011a or newer**, with Simulink, the Parallelization Toolbox, Optimization Toolbox and Global Optimization Toolbox

## Usage 
The Controller Tester can manage test projects and is able to use MATLAB Simulink to manually or automatically simulate controller models. Fault models are used as a basis for describing the problems which occurr when implementing a particular system. The currently used version of MATLAB depends on the version registered as an Automation Server. To change the registered COM Automation Server, type the following command into the MATLAB Console of your chosen version:

    !matlab -regserver

More information is available at: http://www.mathworks.com/help/matlab/call-matlab-com-automation-server.html

**Use a *From Workspace* block for the Desired variable and a *To Workspace* block to export the Actual variable (as Structure or Structure With Time)**

The currently implemented fault models are:

### The Step Fault Model
The Step Fault Model was described by *Matinnejad et. al.* (see above). The automatic test case generation process attempts to maximize the objective function of a requirement in order to find a worst case scenario. The available objective functions are:
* Stability - measures the standard deviation of the controller after a period of time in which it is allowed to reach the desired value. Should be approximately zero for a stable controller.
* Precision  - measures the maximum steady-state error of the controller after a period of time in which it is allowed to reach the desired value. Checks whether the controller has a high steady-state error.
* Smoothness - measures the maximum over- and undershoot of the controller.
* Responsiveness - measures the time it takes for the controller to approximately reach the desired value.
* Steadiness - measures the oscillation in the actual value after a period of time in which it is allowed to reach the desired value.

Besides this, the fault model also checks if the actual values are in the physical range of the process. The particularity of this fault model is that the input signal, the controller's desired value, is a step function. The reasoning behind the fault model is that usually, in a real-life scenario, the controller does not start from 0 (or whatever initial value it may have). Because of this, a real-life scenario of the controller would be one where the initial value is arbitrary (the current actual value) rather than a constant value. To simulate this scenario, two desired values are generated - an initial desired value and a final desired value, and the controller is simulated with each value for half of the time. This scenario also shows the controller's performance in the case of negative calculations (especially in the case of undershoots), which are typically neglected when doing Model-in-the-Loop testing.

The objective functions of each requirement are computed based on the controller's actual value signal after the final desired value is input to it. The intermediate outcome of the test case generation process is a heatmap indicating possible problematic regions in the 2-D input space. The user can choose the regions he wants to investigate further. The final outcome of our test case generation is a worst case test scenario for a particular requirement in a certain region.

### The Disturbance Fault Model

Under the presence of a disturbance, the controller might not able to reach the desired value or might reach it slower than expected, until the opposing force is removed. It could also be the case that, after the removal of this opposing force, the controller achieves a signiﬁcant overshoot while moving to the initially speciﬁed desired value, which now becomes reachable.

The controller is simulated for a certain time *T* using the 2-dimensional input point *p*, made up of the two signals, *Desired(t)* and *Disturbance(t)*. The discretized output of the controller, *Actual(t)* is then evaluated against the requirements presented for the step fault model.

### The Controller Comparison Fault Model

Although the controller is typically implemented in continuous time at the model level, on a microcontroller, the controller has to run in discrete time, with a ﬁxed time step Tstep and a corresponding frequency of f = 1 Tstep. The Laplace transforms of the system’s functions must be converted to Z-transforms, and careful attention needs to be put into choosing a correct discretization time step, since this can cause stability and performance issues. Depending on the type of approximation used, a stable continuous-time controller-plant model can be mapped to an unstable discrete-time model. Furthermore, time delays compared to the continuous-time model will need to be analyzed.

The search process is the same as for the standard step fault model for a single controller, however, the objective functions are different. We measure the difference in the values for the ﬁve objective functions presented for the step fault model between the original and the derived model, and in addition, we measure the average and maximum deviations in the actual value.

### The Allowed Oscillation Fault Model

In the presence of noise when reading the desired value, or simply due to small variations in the desired value, the controller has the requirement not to change the actual value, if the new desired value varies with regard to the actual value of the system by a small percentage *oscallowed[%]*, e.g. by a maximum of 5%.

To check if the controller conforms to the above requirement, we must run the system with two desired values, in a similar way to the step fault model. This combinatorial testing approach allows us to test if there exists a combination of two desired values where the allowed oscillation requirement is voided. The total simulation time should allow for the controller to stabilize upon reaching the initial and ﬁnal desired values.

### The Sine Fault Model

The motivation behind this fault model is checking if the frequency response of the system conforms to the expectations that the control system designer has, for example from looking at the Bode plot of the system's transfer function. It can be the case that the implemented controller does not have the same frequency response because of implementation faults.

## Further development
The tool is designed to be easily extendable with plug-in Controller Fault Models.

## Known issues
* When moving a project from a computer to another or re-installing the application, always re-run the Simulation Settings Validation, since the MATLAB COM Automation Server fails to build the accelerated model. For this purpose please re-validate the simulation settings so that an accelerated model is built, or create a new project on the other PC, since the SimulationWorker contains a workaround for building the accelerated model.
