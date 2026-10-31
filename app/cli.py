import sys
from engine import discover, review
if __name__=='__main__':
 if len(sys.argv)>1 and sys.argv[1]=='discover': print('\n'.join(discover()))
 else:
  alerts=review()
  print('\n'.join(alerts) if alerts else 'No detectable staged rule violations')
  sys.exit(1 if alerts and '--block' in sys.argv else 0)
