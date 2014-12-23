/*
Code originally from Aron Steg: http://forums.electricimp.com/discussion/comment/7904
Modified February 1st, 2014 by Nathan Seidle
Many great fixes were made by Aaron Steg, May 2014.

Currently, the only difference between this code and Aaron's original is we invert
the reset line logic to work with standard Arduinos.

Original license:

Copyright (c) 2014 Electric Imp
The MIT License (MIT)
http://opensource.org/licenses/MIT
*/

server.log("Agent started, URL is " + http.agenturl());

const MAX_PROGRAM_SIZE = 0x20000;
const ARDUINO_BLOB_SIZE = 128;

program <- null;

//------------------------------------------------------------------------------------------------------------------------------
html <- @"
<!doctype html>
<HTML lang='en'>
<head>
<meta name='viewport' content='width=device-width, initial-scale=1.0'>
<!-- Bootstrap -->
<!-- Latest compiled and minified CSS -->
<link rel='stylesheet' href='//maxcdn.bootstrapcdn.com/bootstrap/3.2.0/css/bootstrap.min.css'>
<!-- Optional theme -->
<link rel='stylesheet' href='//maxcdn.bootstrapcdn.com/bootstrap/3.2.0/css/bootstrap-theme.min.css'>
</head>
<BODY>
<div class='container'>
<h1>Program the ATmega328 via the Imp.</h1>
<form method='POST' enctype='multipart/form-data'>
Step 1: Select an Intel HEX file to upload: <input type=file name=hexfile><br/>
Step 2: <input type=submit value=Press> to upload the file.<br/>
Step 3: Check out your Arduino<br/>
</form>
<form method='POST' id='hex-upload-form'>
<input type=hidden name=hexfile id='hex-file'>
</form>
<h2>OR</h2>
<div class='panel panel-default'>
<div class='panel-heading' id='dropbox-button'></div>
<div class='panel-body'>
<table class='table'>
<thead>
<tr>
<th>#</th>
<th>File Name</th>
<th>Action</th>
</tr>
</thead>
<tbody id='link-text'>
</tbody>
</table>
</div>
</div>
</div>

<script src='//ajax.googleapis.com/ajax/libs/jquery/1.11.1/jquery.min.js'></script>
<script src='//maxcdn.bootstrapcdn.com/bootstrap/3.2.0/js/bootstrap.min.js'></script>
<script type='text/javascript' src='//www.dropbox.com/static/api/2/dropins.js' id='dropboxjs' data-app-key='8jsgtlv8g2xgq9s'></script>
<script type='text/javascript'>
function uploadFile(fileLink) {
  $('#hex-file').val(fileLink);
  $('#hex-upload-form').submit();
}
function buildLinkRow(idx, fileLink) {
  $('#link-text').append('<tr id=\'link-row-'+idx+'\'><td>'+idx+'</td><td>'+fileLink+'</td><td><button type=button id=upload-button-'+idx+' class=\'btn btn-default\'><span class=\'glyphicon glyphicon-upload\'></span></button><button type=button id=\'remove-button-'+idx+'\' class=\'btn btn-default\'><span class=\'glyphicon glyphicon-remove\'></span></button></td></tr>');
  $('#upload-button-'+idx).click({value: fileLink}, function(e) {
    uploadFile(e.data.value);
  });
  $('#remove-button-'+idx).click({value: idx, link: fileLink}, function(e) {
    $('#link-row-'+e.data.value).remove();
    links.splice(idx - 1, 1);
    buildLinkTable();
  });
}
function buildLinkTable() {
  $('#link-text').empty();
  if( links.length > 0 ) {
    for( var i=0; i < links.length; i++ ) {
      buildLinkRow(i+1, links[i]);
    } 
    if( window.localStorage ) localStorage['links'] = JSON.stringify(links);
  } else {
    $('#link-text').append('<tr id=\'empty-row\'><td colspan=3>Please select a file.</td></tr>');
  }
}
</script>
<script type='text/javascript'>
options = {
    success: function(files) {
      links.push(files[0].link);
      buildLinkTable();
    },
    cancel: function() {

    },
    linkType: 'direct',
    multiselect: false, 
    extensions: ['.hex']
};
var button = Dropbox.createChooseButton(options);
$('#dropbox-button').html(button);

var emptyRow;
var links = [];
if( window.localStorage ) {
  var linksStr = localStorage['links'];
  if( linksStr ) {
    links = JSON.parse(linksStr);
  }
} else {
  console.log('local storage not supported...');
}
buildLinkTable();

</script>

</BODY>
</HTML>
";

//------------------------------------------------------------------------------------------------------------------------------
// Parses a HTTP POST in multipart/form-data format
function parse_hexpost(req, res) {
    local boundary = req.headers["content-type"].slice(30);
    local bindex = req.body.find(boundary);
    local hstart = bindex + boundary.len();
    local bstart = req.body.find("\r\n\r\n", hstart) + 4;
    local fstart = req.body.find("\r\n\r\n--" + boundary + "--", bstart);
    return req.body.slice(bstart, fstart);
}


//------------------------------------------------------------------------------------------------------------------------------
// Parses a hex string and turns it into an integer
function hextoint(str) {
    local hex = 0x0000;
    foreach (ch in str) {
        local nibble;
        if (ch >= '0' && ch <= '9') {
            nibble = (ch - '0');
        } else {
            nibble = (ch - 'A' + 10);
        }
        hex = (hex << 4) + nibble;
    }
    return hex;
}


//------------------------------------------------------------------------------------------------------------------------------
// Breaks the program into chunks and sends it to the device
function send_program() {
    if (program != null && program.len() > 0) {
        local addr = 0;
        local pline = {};
        local max_addr = program.len();
        
        device.send("burn", {first=true});
        while (addr < max_addr) {
            program.seek(addr);
            pline.data <- program.readblob(ARDUINO_BLOB_SIZE);
            pline.addr <- addr / 2; // Address space is 16-bit
            device.send("burn", pline)
            addr += pline.data.len();
        }
        device.send("burn", {last=true});
    }
}        

//------------------------------------------------------------------------------------------------------------------------------
// Parse the hex into an array of blobs
function parse_hexfile(hex) {
    
    try {
        // Look at this doc to work out what we need and don't. Max is about 122kb.
        // https://bluegiga.zendesk.com/entries/42713448--REFERENCE-Updating-BLE11x-firmware-using-UART-DFU
        server.log("Parsing hex file");
        
        // Create and blank the program blob
        program = blob(0x20000); // 128k maximum
        for (local i = 0; i < program.len(); i++) program.writen(0x00, 'b');
        program.seek(0);
        
        local maxaddress = 0, from = 0, to = 0, line = "", offset = 0x00000000;
        do {
            if (to < 0 || to == null || to >= hex.len()) break;
            from = hex.find(":", to);
            
            if (from < 0 || from == null || from+1 >= hex.len()) break;
            to = hex.find(":", from+1);
            
            if (to < 0 || to == null || from >= to || to >= hex.len()) break;
            line = hex.slice(from+1, to);
            // server.log(format("[%d,%d] => %s", from, to, line));
            
            if (line.len() > 10) {
                local len = hextoint(line.slice(0, 2));
                local addr = hextoint(line.slice(2, 6));
                local type = hextoint(line.slice(6, 8));

                // Ignore all record types except 00, which is a data record. 
                // Look out for 02 records which set the high order byte of the address space
                if (type == 0) {
                    // Normal data record
                } else if (type == 4 && len == 2 && addr == 0 && line.len() > 12) {
                    // Set the offset
                    offset = hextoint(line.slice(8, 12)) << 16;
                    if (offset != 0) {
                        server.log(format("Set offset to 0x%08X", offset));
                    }
                    continue;
                } else {
                    server.log("Skipped: " + line)
                    continue;
                }

                // Read the data from 8 to the end (less the last checksum byte)
                program.seek(offset + addr)
                for (local i = 8; i < 8+(len*2); i+=2) {
                    local datum = hextoint(line.slice(i, i+2));
                    program.writen(datum, 'b')
                }
                
                // Checking the checksum would be a good idea but skipped for now
                local checksum = hextoint(line.slice(-2));
                
                /// Shift the end point forward
                if (program.tell() > maxaddress) maxaddress = program.tell();
                
            }
        } while (from != null && to != null && from < to);

        // Crop, save and send the program 
        server.log(format("Max address: 0x%08x", maxaddress));
        program.resize(maxaddress);
        send_program();
        server.log("Free RAM: " + (imp.getmemoryfree()/1024) + " kb")
        return true;
        
    } catch (e) {
        server.log(e)
        return false;
    }
    
}


//------------------------------------------------------------------------------------------------------------------------------
// Handle the agent requests
http.onrequest(function (req, res) {
    // return res.send(400, "Bad request");
    // server.log(req.method + " to " + req.path)
    if (req.method == "GET") {
        res.send(200, html);
    } else if (req.method == "POST") {

        if ("content-type" in req.headers) {
            if (req.headers["content-type"].len() >= 19
             && req.headers["content-type"].slice(0, 19) == "multipart/form-data") {
                local hex = parse_hexpost(req, res);
                if (hex == "") {
                    res.header("Location", http.agenturl());
                    res.send(302, "HEX file uploaded");
                } else {
                    device.on("done", function(ready) {
                        res.header("Location", http.agenturl());
                        res.send(302, "HEX file uploaded");                        
                        server.log("Programming completed")
                    })
                    server.log("Programming started")
                    parse_hexfile(hex);
                }
            } else if (req.headers["content-type"] == "application/json") {
                local json = null;
                try {
                    json = http.jsondecode(req.body);
                } catch (e) {
                    server.log("JSON decoding failed for: " + req.body);
                    return res.send(400, "Invalid JSON data");
                }
                local log = "";
                foreach (k,v in json) {
                    if (typeof v == "array" || typeof v == "table") {
                        foreach (k1,v1 in v) {
                            log += format("%s[%s] => %s, ", k, k1, v1.tostring());
                        }
                    } else {
                        log += format("%s => %s, ", k, v.tostring());
                    }
                }
                server.log(log)
                return res.send(200, "OK");
            } else if(req.headers["content-type"] == "application/x-www-form-urlencoded") {
              server.log(req.body);
              local data = http.urldecode(req.body);
              local url = data.hexfile;
              server.log("url: " + url);
              local hex = http.get(url).sendsync();
              //server.log("hex: " + hex.body);
              device.on("done", function(ready) {
                  res.header("Location", http.agenturl());
                  res.send(302, "HEX file uploaded");                        
                  server.log("Programming completed")
              })
              server.log("Programming started")
              parse_hexfile(hex.body);              
            } else {          
                return res.send(400, "Bad request");
            }
        } else {
            return res.send(400, "Bad request");
        }
    }
})


//------------------------------------------------------------------------------------------------------------------------------
// Handle the device coming online
device.on("ready", function(ready) {
    if (ready) send_program();
});