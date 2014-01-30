Tomatoless Boots
==================

A wireless bootloader for Arduino with an Electric Imp. Using an Imp on the [SparkFun Electric Imp Shield](https://www.sparkfun.com/products/11401) you can reprogram an Arduino anywhere in the world by pushing a HEX file to a webpage. It's *really* slick and easy to use.

There are two bits of code to load onto the Imp, the device and agent. Two hardware modifications to the [Electric Imp Shield](https://www.sparkfun.com/products/11401) from SparkFun are required:

* Cut two RX/TX traces to 8/9 on the back of the Imp Shield then solder blob to 0/1
* Wire from P1 of Imp to RST on shield.

This code includes improvements to decrease the time it takes to bootload a program from tens of seconds to under a second.

License Information
-------------------

This code (written by [blindman2k](https://github.com/electricimp/reference/tree/master/hardware/impeeduino)) is released with an [MIT license](http://opensource.org/licenses/MIT).