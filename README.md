# 🔋 NVBatMan
> Fix NVIDIA GPUs hogging all that battery power!

Modern laptop GPUs may not always match their desktop counterparts, but they pack a pretty powerful punch in their own right. But as they say, with great power comes great power consumption. Sadly, many laptop manufacturers don't put a lot of thought into optimizing for on-battery performance. This can result in sluggish system performance as other components throttle to make up for the GPU consuming all available power. Most of the time, users are recommended to simply disable it in favor of an integrated GPU instead.

Well, no longer! Even when power-constrained, dGPUs often far outperform iGPUs, and you should be able to use them!

## About
**NVBatMan** is an NVIDIA battery manager utility for Windows laptops. It is comprised of a small PowerShell script and a Task Scheduler activity to run it when switching between AC and DC. 

The PowerShell script calls the `nvidia-smi` CLI application included with the official NVIDIA driver package to limit GPU clock speeds to safe ranges for battery operation. This avoids competing with the CPU for battery power, increasing overall system performance vs stock clocks. To avoid clock limits being overridden, the `NVIDIA Platform Controllers and Framework` driver is also temporarily disabled while in this state.

Power limiting is achieved via memory and graphics clocks rather than modifying TGP directly to support the widest range of laptops possible. (Most laptop GPUs lock the user out of modifying TGP.) Exact clocks are selected programmatically, ensuring compatible frequency pairs as reported by `nvidia-smi` regardless of your exact model of GPU.

## How to Use

#### To Install:
1. If your laptop features NVIDIA Optimus, ensure it is set to "Optimus" (see below).
2. Download the latest version of `NVBatMan.bat` from this repository.
3. Run it.

#### To Uninstall:
1. Run `NVBatMan.bat` again and it'll undo all changes to your system.

#### To Update:
1. Run `NVBatMan.bat` to uninstall previous versions
2. Run `NVBatMan.bat` again to install the new version

Note that changes made by NVBatMan are permanent until uninstalled, so you do not need to keep the installer on your PC after installation.

### "Which performance mode should I use?"
During installation, NVBatMan offers two performance modes: **Balanced** and **Performance**.

* **Balanced Mode** aims for stability above all else. Overall FPS may be lower in games, but you'll get fewer power-related stutters due to various hardware competing for limited watts.
  * This mode prioritizes graphics clocks over memory clocks.
* **Performance Mode** is primarily for systems with larger batteries and higher TDPs. The GPU will be less constrained, but may occasionally steal power from other components, resulting in temporary hitches or lag.
  * This mode prioritizes memory clocks over graphics clocks.
 
For most users, **Balanced Mode is recommended**. However, you can easily switch between modes by simply re-running the NVBatMan installer, so feel free to test both and see what works best for your system.

## Known Issues
* **Does not support NVIDIA Optimus in "NVIDIA GPU" mode!** Running the entire display on the NVIDIA GPU with limited power can result in massive lag!
* **May not accurately detect USB-C power sources!** As of v1.0.3, NVBatMan will attempt to detect when an insufficient power source is connected and enable power limiting even while charging. Currently, this is done by checking whether NVIDIA automatically selects a TGP lower than the default setting. However, this condition can sometimes occur even on AC power, resulting in throttle. **If this happens**, run the "Stop NVBatMan" Start Menu shortcut added in v1.0.5 to return to normal power management.
  * There is also a "Start NVBatMan" shortcut in case the reverse happens.
  * These shortcuts do not override the Task Scheduler service--NVBatMan will continue to *attempt* to do its thing whenever further changes in power status are detected.
