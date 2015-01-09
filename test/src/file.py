import configparser
import os

BASEDIR = os.path.normpath(os.path.join(os.path.dirname(__file__), os.pardir))

_config = configparser.ConfigParser()
_config.read(os.path.join(BASEDIR, 'config.ini'))
config = _config['FILE']


def save(key, value):
    with open(config['KEYSTORE'], "a") as keystore:
        keystore.write("{} = {}\n".format(key, value))


def fetch(key):
    with open(config['KEYSTORE'], "r") as keystore:
        for line in keystore:
            if(line.startswith(key + " = ")):
                val = line[line.index("=")+2:]
    return val.strip()
